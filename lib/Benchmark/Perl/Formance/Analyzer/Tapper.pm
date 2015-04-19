package Benchmark::Perl::Formance::Analyzer::Tapper;
# ABSTRACT: Benchmark::Perl::Formance - analyze results

use 5.010;

use Moose;
use File::Find::Rule;
use Data::DPath "dpath";
use Data::Dumper;
use TryCatch;
use version 0.77;
use Data::Structure::Util 'unbless';

with 'MooseX::Getopt::Usage',
 'MooseX::Getopt::Usage::Role::Man';

has 'subdir'     => ( is => 'rw', isa => 'ArrayRef', documentation => "where to search for benchmark results", default => sub{[]} );
has 'name'       => ( is => 'rw', isa => 'ArrayRef', documentation => "file name pattern" );
has 'verbose'    => ( is => 'rw', isa => 'Bool',     documentation => "Switch on verbosity" );
has 'blacklist'  => ( is => 'rw', isa => 'Str',      documentation => "metrics to skip (regular expression)" );
has '_RESULTS'   => ( is => 'rw', isa => 'ArrayRef', default => sub{[]} );

use namespace::clean -except => 'meta';
__PACKAGE__->meta->make_immutable;
no Moose;

use PDL;
use PDL::Primitive;

sub print_version
{
        my ($self) = @_;

        if ($self->verbose)
        {
                print "Benchmark::Perl::Formance::Analyzer version $Benchmark::Perl::Formance::Analyzer::VERSION\n";
        }
        else
        {
                print $Benchmark::Perl::Formance::Analyzer::VERSION, "\n";
        }
};

sub _analyze_single_file
{
        my ($self, $file) = @_;

        my $data;
        my @chunks;

        say "- $file" if $self->verbose;

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
                say "  ERROR: $file : $err" if $self->verbose;
        };
        return @chunks;
}

sub _process_results
{
        my ($self, $results) = @_;


        # unused but keep for a while
        my $order_by_version = sub { version->parse($a->{perlconfig_version}) <=> version->parse($b->{perlconfig_version}) };
        my $order_by_VALUE   = sub { $a->{VALUE} <=> $b->{VALUE} };
        my %ordering = ( version => $order_by_version,
                         VALUE   => $order_by_VALUE,
                       );

        my %results_by_NAME;
        push @{$results_by_NAME{$_->{NAME}}}, $_ foreach @$results;

        my %results_by_VERSION;
        push @{$results_by_VERSION{$_->{perlconfig_version}}}, $_ foreach @$results;

        my $blacklist = $self->blacklist;
        my @metrics  = grep { not $blacklist or $_ !~ qr/$blacklist/ } sort keys %results_by_NAME;
        my @versions = sort {version->parse($a) <=> version->parse($b)} keys %results_by_VERSION;

        my %RESULTS;

        foreach my $NAME (@metrics) {

                my $sub_results = $results_by_NAME{$NAME};

                say "# $NAME" if $self->verbose;
                my %multi_values;
                foreach my $r (@$sub_results) {
                        say "  raw:", $r->{perlconfig_version}, ":", $r->{NAME}, ":", $r->{VALUE} if $self->verbose;
                        push @{$multi_values{$r->{perlconfig_version}}}, $r->{VALUE};
                }
                foreach my $v (keys %multi_values) {
                        my $pdl = PDL::Core::pdl($multi_values{$v});
                        my ($mean,$prms,$median,$min,$max,$adev,$rms) = PDL::Primitive::stats($pdl);
                        say "  avg:$v:$NAME:$mean($adev)" if $self->verbose;
                        $RESULTS{$NAME}{$v} = "$mean";
                }
                say "" if $self->verbose;
        }

        # ['VERSION', 'dpath', 'Mem', 'Fib'],
        # ['2013',  1000,      400,     100],
        # ['2014',  1170,      460,     100],
        # ['2015',  660,       1120,    100],
        # ['2016',  1030,      540,     200]

        my $RESULTMATRIX;

        $RESULTMATRIX->[0][0] = 'VERSION';
        foreach (0..$#metrics) {
                my $m = $metrics[$_] || "undef";
                $m =~ s/perlformance.perl5.//;
                $RESULTMATRIX->[0][$_+1] = $m;
        }

        for (my $i=0; $i < @versions; $i++)
        {
                my $version = $versions[$i];

                $RESULTMATRIX->[$i+1][0] = $version;
                for (my $j=0; $j < @metrics; $j++)
                {
                        my $metric = $metrics[$j];
                        $RESULTMATRIX->[$i+1][$j+1] = 0+($RESULTS{$metric}{$version} || 0);
                }
        }

        require JSON;
        print JSON->new->pretty->encode( $RESULTMATRIX );
}

sub _analyze_localfiles
{
        my ($self) = @_;

        say "Process subdirs: ".join(":", @{$self->subdir}) if $self->verbose;

        my @results;
        my @pattern  = @{$self->name || ["*.yaml", "*.json"]};
        my @files    = File::Find::Rule->file->name(@pattern)->in(@{$self->subdir});
        push @results, $self->_analyze_single_file($_) foreach @files;

        @results = grep { $_->{NAME} =~ /^perlformance.perl5./ } @results;
        $self->_process_results(\@results);
}

sub run
{
        my ($self) = @_;

        $self->_analyze_localfiles if @{$self->subdir};
        say "Done." if $self->verbose;

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
