#! /usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::More 0.88;
use Test::Deep 'cmp_deeply';
use Benchmark::Perl::Formance::Analyzer::Tapper;

my $input;
my $output;
my $expected;

my $analyzer = Benchmark::Perl::Formance::Analyzer::Tapper->new_with_options;

$input = [
          { title => "dpath-T-n64",
            results => [
                        {NAME => "dpath", VALUE => 1000, version => "2.0.13"},
                        {NAME => "dpath", VALUE => 1170, version => "2.0.14"},
                        {NAME => "dpath", VALUE =>  660, version => "2.0.15"},
                        {NAME => "dpath", VALUE => 1030, version => "2.0.16"},
                       ],
          },
          { title => "Mem-nT-n64",
            results => [
                        {NAME => "Mem",   VALUE =>  400, version => "2.0.13"},
                        {NAME => "Mem",   VALUE =>  460, version => "2.0.14"},
                        {NAME => "Mem",   VALUE => 1120, version => "2.0.15"},
                        {NAME => "Mem",   VALUE =>  540, version => "2.0.16"},
                       ],
          },
          { title => "Fib-T-64",
            results => [
                        {NAME => "Fib",   VALUE => 100, version => "2.0.13"},
                        {NAME => "Fib",   VALUE => 100, version => "2.0.14"},
                        {NAME => "Fib",   VALUE => 100, version => "2.0.15"},
                        {NAME => "Fib",   VALUE => 200, version => "2.0.16"},
                       ],
          },
         ];

$expected = [
   [
      "VERSION",
      "dpath-T-n64",
      "Mem-nT-n64",
      "Fib-T-64",
   ],
   [
      "2.0.13",
      1000,
      400,
      100,
   ],
   [
      "2.0.14",
      1170,
      460,
      100,
   ],
   [
      "2.0.15",
      660,
      1120,
      100,
   ],
   [
      "2.0.16",
      1030,
      540,
      200,
   ],
]
;

$output = $analyzer->_process_results($input);
cmp_deeply($output, $expected, "data transformation - google areachart");



# Finish
ok(1, "dummy");
done_testing;
