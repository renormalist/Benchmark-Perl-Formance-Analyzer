package Benchmark::Perl::Formance::Analyzer::Tapper;
# ABSTRACT: Benchmark::Perl::Formance - analyze results

use 5.010;

use Moose;
use File::Find::Rule;
use namespace::clean;
use List::MoreUtils "uniq";
use Data::DPath "dpath";
use Data::Dumper;
use YAML;

with 'MooseX::Getopt::Usage',
 'MooseX::Getopt::Usage::Role::Man';

has 'localdir' => ( is => 'rw', isa => 'ArrayRef', documentation => "where to search for benchmark results.", default => sub{[]} );
has 'verbose'  => ( is => 'rw', isa => 'Bool',     documentation => "Switch on verbosity." );
has '_RESULTS' => ( is => 'rw', isa => 'ArrayRef', default => sub{[]} );

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

sub _get_BAD
{

}

sub _analyze_single_file
{
        my ($self, $file) = @_;

        my $data;
        my @chunks;

        say "- $file" if $self->verbose;

        if ($file =~ /ya?ml$/) {
                $data = YAML::LoadFile($file);
        } elsif ($file =~ /json$/) {
                $data = YAML::LoadFile($file);
        }
        print Dumper($data);
        @chunks = dpath($data)->match("//BenchmarkAnythingData");
        print Dumper($_) foreach @chunks;
}

sub _analyze_localfiles
{
        my ($self) = @_;

        say "Process subdirs: ".join(":", @{$self->localdir}) if $self->verbose;

        my @files = File::Find::Rule->file->name("*.yaml", "*.json")->in(@{$self->localdir});
        $self->_analyze_single_file($_) foreach @files;

}

sub run
{
        my ($self) = @_;

        $self->_analyze_localfiles if @{$self->localdir};
        say "Done." if $self->verbose;

        return;
}

1;

__END__

=head1 ABOUT

Analyze L<Benchmark::Perl::Formance|Benchmark::Perl::Formance> results.

=head1 METHODS

=head2 run

Entry point to actually start.

=head2 print_version

Print version.

=cut
