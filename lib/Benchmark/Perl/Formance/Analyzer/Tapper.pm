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

with 'MooseX::Getopt::Usage',
 'MooseX::Getopt::Usage::Role::Man';

has 'subdir'     => ( is => 'rw', isa => 'ArrayRef', documentation => "where to search for benchmark results", default => sub{[]} );
has 'name'       => ( is => 'rw', isa => 'ArrayRef', documentation => "file name pattern" );
has 'verbose'    => ( is => 'rw', isa => 'Bool',     documentation => "Switch on verbosity" );
has 'debug'      => ( is => 'rw', isa => 'Bool',     documentation => "Switch on debugging output" );
has 'whitelist'  => ( is => 'rw', isa => 'Str',      documentation => "metricss to use (regular expression)" );
has 'blacklist'  => ( is => 'rw', isa => 'Str',      documentation => "metrics to skip (regular expression)" );
has '_RESULTS'   => ( is => 'rw', isa => 'ArrayRef', default => sub{[]} );
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
                                             INCLUDE_PATH => dist_dir('Benchmark-Perl-Formance-Analyzer'), # or list ref
                                             INTERPOLATE  => 0,       # expand "$var" in plain text
                                             POST_CHOMP   => 0,       # cleanup whitespace
                                             EVAL_PERL    => 0,       # evaluate Perl code blocks
                                            });
                      }
                    );
has 'x_key'       => ( is => 'rw', isa => 'Str',      documentation => "xAxis key", default => "perlconfig_version" );
has 'x_type'      => ( is => 'rw', isa => 'Str',      documentation => "xAxis key", default => "version" ); # version, numeric, string, date
has 'y_key'       => ( is => 'rw', isa => 'Str',      documentation => "xAxis key", default => "VALUE" );
has 'y_type'      => ( is => 'rw', isa => 'Str',      documentation => "xAxis key", default => "numeric" );
has 'aggregation' => ( is => 'rw', isa => 'Str',      documentation => "xAxis key", default => "avg" );     # sub entries of {stats}: avg, stdv, ci_95_lower, ci_95_upper

use namespace::clean -except => 'meta';
__PACKAGE__->meta->make_immutable;
no Moose;

# use PDL::LiteF;
# use PDL::NiceSlice;
require PDL::Stats::Basic;
require PDL::Ufunc;

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

sub _fetch_from_single_file
{
        my ($self, $file) = @_;

        my $data;
        my @chunks;

        say STDERR "- $file" if $self->verbose;

        try {
                if ($file =~ /ya?ml$/)
                {
                        # read
                        local $/;
                        open my $fh, '<', $file;
                        my $yaml = <$fh>;
                        close $fh;

                        # remove YAMLish end marker
                        $yaml =~ s/^\.{3}$//m;

                        # load
                        require YAML;
                        $data = YAML::Load($yaml);
                }
                elsif ($file =~ /json$/)
                {
                        require JSON;
                        local $/;
                        open my $fh, '<', $file;
                        $data = JSON::decode_json(<$fh>);
                        close $fh;
                }
                @chunks = dpath("//BenchmarkAnythingData/*/NAME/..")->match($data);
        } catch($err) {
                say STDERR "  ERROR: $file : $err" if $self->verbose;
        }
        ;
        return @chunks;
}

sub _tt_filename
{
        my ($self) = @_;

        dist_dir('Benchmark-Perl-Formance-Analyzer').'/'.$self->template;

        # # template
        # my $filename;

        # # include paths
        # my @subdirs = ( "share",  );
        # my $subdir; # pre-declare to later re-use last assignment
        # foreach $subdir (@subdirs) {
        #         last if -e $filename;
        # }
        # return $filename;
}

sub _print_to_template
{
        my ($self, $RESULTMATRIX) = @_;

        require JSON;

        # print
        my $vars = {
                    RESULTMATRIX     => JSON->new->pretty->encode( $RESULTMATRIX ),

                    title            => 'Perl::Formance benchmarks',
                    x_key            => $self->x_key,
                    isStacked        => "false",  # true, false, 'relative'
                    interpolateNulls => "true",   # true, false -- only works with isStacked=false
                    areaOpacity      => 0.0,
                   };

        # to STDOUT
        $self->tt->process($self->template, $vars)
         or die $self->tt->error."\n";
}

# ASSUMPTION: there is only one NAME per chartline
# ASSUMPTION: titles are unique
#
# INPUT:
# [ title: dpath-T-n64
#   {N:dpath, V:1000, version:2013},
#   {N:dpath, V:1170, version:2014},
#   {N:dpath,  V:660, version:2015},
#   {N:dpath, V:1030, version:2016},
# ],
# [ title: Mem-nT-n64
#   {N:Mem,    V:400, version:2013},
#   {N:Mem,    V:460, version:2014},
#   {N:Mem,   V:1120, version:2015},
#   {N:Mem,    V:540, version:2016},
# ],
# [ title: Fib-T-64
#   {N:Fib,    V:100, version:2013},
#   {N:Fib,    V:100, version:2014},
#   {N:Fib,    V:100, version:2015},
#   {N:Fib,    V:200, version:2016},
# ]
#
# OUTPUT:
#
# ['VERSION', 'dpath', 'Mem', 'Fib'],
# ['2013',      1000,   400,   100],
# ['2014',      1170,   460,   100],
# ['2015',       660,  1120,   100],
# ['2016',      1030,   540,   200]

sub multi_point_stats
{
        my ($self, $values) = @_;

        my $data = PDL::Core::pdl(@$values);
        my $avg  = PDL::Stats::Basic::average($data);
        return {
                avg         => PDL::Core::sclr($avg),
                stdv        => PDL::Stats::Basic::stdv($data),
                min         => PDL::Ufunc::min($data),
                max         => PDL::Ufunc::max($data),
                ci_95_lower => $avg - 1.96 * PDL::Stats::Basic::se($data),
                ci_95_upper => $avg + 1.96 * PDL::Stats::Basic::se($data),
               };
}

sub _process_results
{
        my ($self, $chartlines) = @_;

        my $x_key       = $self->x_key;
        my $x_type      = $self->x_type;
        my $y_key       = $self->y_key;
        my $y_type      = $self->y_type;
        my $aggregation = $self->aggregation;

        # from all chartlines collect values into buckets for the dimensions we need
        #
        # chartline = title
        # x         = perlconfig_version
        # y         = VALUE
        my %VALUES;
        foreach my $chartline (@$chartlines)
        {
                my $title     = $chartline->{title};
                my $results   = $chartline->{results};
                my $NAME      = $results->[0]{NAME};

                say STDERR sprintf("* %-20s - %-40s", $title, $NAME) if $self->verbose;

                foreach my $point (@$results)
                {
                        my $x = $point->{$x_key};
                        my $y = $point->{$y_key};
                        push @{$VALUES{$title}{$x}{values}}, $y; # maybe multiple for same X - average them later
                }
        }

        # statistical aggregations of multi points
        foreach my $title (keys %VALUES)
        {
                foreach my $x (keys %{$VALUES{$title}})
                {
                        my $multi_point_values     = $VALUES{$title}{$x}{values};
                        $VALUES{$title}{$x}{stats} = $self->multi_point_stats($multi_point_values);
                }
        }

        # find out all available x-values from all chartlines
        my %all_x;
        foreach my $title (keys %VALUES)
        {
                foreach my $x (keys %{$VALUES{$title}})
                {
                        $all_x{$x} = 1;
                }
        }
        my @all_x = keys %all_x;

        # drop complete chartlines if it has gaps on versions that the other chartlines provide values
        my %clean_chartlines;
        if ($self->dropnull) {
                foreach my $title (keys %VALUES) {
                        my $ok = 1;
                        foreach my $x (@all_x) {
                                #say STDERR "$title / $x: ".join(",", @{$VALUES{$title}{$x}{values} || []}) if $self->verbose;
                                if (not @{$VALUES{$title}{$x}{values} || []}) {
                                        say STDERR "skip: $title (missing values for $x)" if $self->verbose;
                                        $ok = 0;
                                }
                        }
                        if ($ok) {
                                $clean_chartlines{$title} = 1;
                                say STDERR "okay: $title" if $self->verbose;
                        }
                }
        }

        # intermediate debug output
        foreach my $title (keys %VALUES)
        {
                foreach my $x (keys %{$VALUES{$title}})
                {
                        my $count = scalar @{$VALUES{$title}{$x}{values} || []} || 0;
                        next if not $count;
                        my $avg   = $VALUES{$title}{$x}{stats}{avg};
                        my $stdv  = $VALUES{$title}{$x}{stats}{stdv};
                        my $ci95l = $VALUES{$title}{$x}{stats}{ci_95_lower};
                        my $ci95u = $VALUES{$title}{$x}{stats}{ci_95_upper};
                        say STDERR sprintf("%-20s . %-7s . avg = %7.2f +- %5.2f (%3d points)", $title, $x, $avg, $stdv, $count) if $self->verbose;
                }
        }

        # result data structure, as needed per chart type
        my @RESULTMATRIX;

        my @titles =
         grep { !$self->dropnull or $clean_chartlines{$_} }    # dropnull
          # sort by comparing value of latest version
          # (only works when latest version has values for each chartline...)
          # sort { $VALUES{$a}{$all_x[-1]}{stats}{$aggregation} <=> $VALUES{$b}{$all_x[-1]}{stats}{$aggregation} }
          sort
           keys %VALUES;

        for (my $i=0; $i<@all_x; $i++)          # rows
        {
                my $x = $all_x[$i];
                for (my $j=0; $j<@titles; $j++) # columns
                {
                        my $title = $titles[$j];
                        my $value = $VALUES{$title}{$x}{stats}{$aggregation};
                        $RESULTMATRIX[0]    [0]    = "VERSION"    if $i == 0 && $j == 0;
                        $RESULTMATRIX[0]    [$j+1] = $title       if $i == 0;
                        $RESULTMATRIX[$i+1] [0]    = $x           if            $j == 0;
                        $RESULTMATRIX[$i+1] [$j+1] = $value ? (0+$value) : undef; # stringify, then numify PDL
                }
        }
        return \@RESULTMATRIX;
}

sub _get_queries
{
        my ($self) = @_;

        # list of queries inclusive description to be used later
        return
         [
          {
           title => "binarytrees-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.Shootout.binarytrees" ],
                                    ],
                       "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "fasta-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.Shootout.fasta" ],
                                    ],
                      "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "nbody-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.Shootout.nbody" ],
                                    ],
                      "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "spectralnorm-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.Shootout.spectralnorm" ],
                                    ],
                      "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "dpath-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.DPath.dpath" ],
                                    ],
                       "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "viv-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.P6STD.viv" ],
                                      [">" , "VALUE", 1 ], # ignore bogus low values
                                    ],
                       "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
          {
           title => "threadstorm-any",
           query => { "where"    => [ ["=" , "NAME", "perlformance.perl5.Threads.threadstorm" ],
                                    ],
                       "select"   => [ "NAME", "VALUE", "perlconfig_version" ],
                      "order_by" => [ "VALUE_ID" ],
                    },
          },
         ];
}

sub _search
{
        my ($self) = @_;

        $self->balib->connect;

        my @results;
        foreach my $q (@{$self->_get_queries})
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

        my $results       = $self->_search();
        my $result_matrix = $self->_process_results($results);
        $self->_print_to_template($result_matrix);

        say STDERR "Done." if $self->verbose;

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

  $ benchmark-perlformance-process-tapper --subdir=path/to/results

It finds all files below the given subdirectory which match one of the
supported formats C<json> or C<yaml>, and processes their data.

=head1 METHODS

=head2 run

Entry point to actually start.

=head2 print_version

Print version.

=cut
