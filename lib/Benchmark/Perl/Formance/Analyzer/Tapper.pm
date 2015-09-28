package Benchmark::Perl::Formance::Analyzer::Tapper;
# ABSTRACT: Benchmark::Perl::Formance - analyze results using Tapper backend store

use 5.010;

use Moose;
use File::Find::Rule;
use Data::DPath "dpath";
use Data::Dumper;
use TryCatch;
use version 0.77;
use Data::Structure::Util 'unbless';
use File::ShareDir 'dist_dir';
use BenchmarkAnything::Storage::Frontend::Lib;
use Template;
use JSON 'decode_json';

with 'MooseX::Getopt::Usage',
 'MooseX::Getopt::Usage::Role::Man';

has 'subdir'     => ( is => 'rw', isa => 'ArrayRef', documentation => "where to search for benchmark results", default => sub{[]} );
has 'name'       => ( is => 'rw', isa => 'ArrayRef', documentation => "file name pattern" );
has 'outfile'    => ( is => 'rw', isa => 'Str',      documentation => "output file" );
has 'verbose'    => ( is => 'rw', isa => 'Bool',     documentation => "Switch on verbosity" );
has 'debug'      => ( is => 'rw', isa => 'Bool',     documentation => "Switch on debugging output" );
has 'whitelist'  => ( is => 'rw', isa => 'Str',      documentation => "metricss to use (regular expression)" );
has 'blacklist'  => ( is => 'rw', isa => 'Str',      documentation => "metrics to skip (regular expression)" );
has 'dropnull'   => ( is => 'rw', isa => 'Bool',     documentation => "Drop metrics with null values", default => 0 );
has 'query'      => ( is => 'rw', isa => 'Str',      documentation => "Search query file or '-' for STDIN", default => "-" );
has 'balib'      => ( is => 'rw',                    documentation => "where to search for benchmark results", default => sub { BenchmarkAnything::Storage::Frontend::Lib->new } );
has 'template'   => ( is => 'rw', isa => 'Str',
                      documentation => 'output template file',
                      default => 'google-chart-area.tt',
                      #default => 'google-chart-line.tt',
                    );
has 'tt'         => ( is => 'rw',
                      documentation => "template renderer",
                      default => sub
                      {
                              Template->new({
                                             INCLUDE_PATH => dist_dir('Benchmark-Perl-Formance-Analyzer')."/templates", # or list ref
                                             INTERPOLATE  => 0,       # expand "$var" in plain text
                                             POST_CHOMP   => 0,       # cleanup whitespace
                                             EVAL_PERL    => 0,       # evaluate Perl code blocks
                                            });
                      }
                    );
has 'x_key'       => ( is => 'rw', isa => 'Str',      documentation => "x-axis key",  default => "perlconfig_version" );
has 'x_type'      => ( is => 'rw', isa => 'Str',      documentation => "x-axis type", default => "version" ); # version, numeric, string, date
has 'y_key'       => ( is => 'rw', isa => 'Str',      documentation => "y-axis key",  default => "VALUE" );
has 'y_type'      => ( is => 'rw', isa => 'Str',      documentation => "y-axis type", default => "numeric" );
has 'aggregation' => ( is => 'rw', isa => 'Str',      documentation => "which aggregation to use (avg, stdv, ci_95_lower, ci_95_upper)", default => "avg" );     # sub entries of {stats}: avg, stdv, ci_95_lower, ci_95_upper

use namespace::clean -except => 'meta';
__PACKAGE__->meta->make_immutable;
no Moose;

sub print_version
{
        my ($self) = @_;

        if ($self->verbose)
        {
                print STDERR "Benchmark::Perl::Formance::Analyzer version $Benchmark::Perl::Formance::Analyzer::VERSION\n";
        }
        else
        {
                print STDERR $Benchmark::Perl::Formance::Analyzer::VERSION, "\n";
        }
}

sub _print_to_template
{
        my ($self, $RESULTMATRIX, $options) = @_;

        require JSON;

        # print
        my $vars = {
                    RESULTMATRIX     => JSON->new->pretty->encode( $RESULTMATRIX ),
                    title            => 'Perl::Formance - '.($options->{charttitle} || ""),
                    x_key            => $options->{x_key},
                    isStacked        => $options->{isStacked},
                    interpolateNulls => $options->{interpolateNulls},
                    areaOpacity      => $options->{areaOpacity},
                   };

        # to STDOUT
        my $outfile = $options->{outfile};

        $self->tt->process($self->template, $vars, ($outfile eq '-' ? () : $outfile))
         or die $self->tt->error."\n";
}

sub _get_chart
{
        my ($self, $chartname) = @_;

        require File::Slurper;

        my $filename = dist_dir('Benchmark-Perl-Formance-Analyzer')."/chartqueries/perlformance/$chartname.json";
        my $json = File::Slurper::read_text($filename);
        if ($self->debug) {
                say STDERR "READ: $chartname - $filename";
                say STDERR "JSON:\n$json";
        }
        return decode_json($json);
}

sub _search
{
        my ($self, $chartline_queries) = @_;

        $self->balib->connect;

        my @results;
        foreach my $q (@{$chartline_queries})
        {
                push @results,
                {
                 title   => $q->{title},
                 results => $self->balib->search($q->{query}),
                };
        }

        return \@results;
}

sub run
{
        my ($self) = @_;

        require File::Find::Rule;
        require File::Basename;
        require BenchmarkAnything::Evaluations;

        say STDERR sprintf("Perl::Formance - chart rendering: ".~~gmtime."\n") if $self->verbose;

        my @chartnames =
         map { File::Basename::basename($_, ".json") }
          File::Find::Rule
                   ->file
                    ->name( '*.json' )
                     ->in( dist_dir('Benchmark-Perl-Formance-Analyzer')."/chartqueries/perlformance/" );

        foreach my $chartname (@chartnames)
        {

                my $chart             = $self->_get_chart($chartname);
                my $chartlines        = $self->_search($chart->{chartlines});
                my $transform_options = {
                                         x_key       => $self->x_key,
                                         x_type      => $self->x_type,
                                         y_key       => $self->y_key,
                                         y_type      => $self->y_type,
                                         aggregation => $self->aggregation,
                                         verbose     => $self->verbose,
                                         debug       => $self->debug,
                                        };
                my $result_matrix = BenchmarkAnything::Evaluations::transform_chartlines($chartlines, $transform_options);

                my $outfile;
                if (not $outfile  = $self->outfile)
                {
                        require File::HomeDir;
                        $outfile  =  $chartname;
                        $outfile  =~ s/[\s\W:]+/-/g;
                        $outfile .=  ".html";
                        $outfile  = File::HomeDir->my_home . "/perlformance/results/".$outfile;
                }
                my $render_options = {
                                      x_key            => $self->x_key,
                                      charttitle       => ($chart->{charttitle} || $chartname),
                                      isStacked        => "false", # true, false, 'relative'
                                      interpolateNulls => "true", # true, false -- only works with isStacked=false
                                      areaOpacity      => 0.0,
                                      outfile          => $outfile,
                                     };
                $self->_print_to_template($result_matrix, $render_options);

                say STDERR "Done." if $self->verbose;

        }
        return;
}

1;

__END__

=head1 ABOUT

Analyze L<Benchmark::Perl::Formance|Benchmark::Perl::Formance> results.

This is a commandline tool to process Benchmark::Perl::Formance
results which follow the L<Tapper|http://tapper-testing.org> benchmark
schema I<BenchmarkAnythingData> as produced with
C<benchmark-perlformance --tapper>.

=head1 SYNOPSIS

Usage:

  $ benchmark-perlformance-process-tapper

=head1 METHODS

=head2 run

Entry point to actually start.

=head2 print_version

Print version.

=cut
