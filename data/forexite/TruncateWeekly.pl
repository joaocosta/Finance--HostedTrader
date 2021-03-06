#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Finance::HostedTrader::Config;
use Data::Dumper;

my ( $timeframes_txt, $symbols_txt );

my $result =
  GetOptions( "timeframes=s", \$timeframes_txt, "symbols=s", \$symbols_txt, );

my $cfg = Finance::HostedTrader::Config->new();

my $symbols;
if ( !defined($symbols_txt) ) {
    $symbols = $cfg->symbols->all;
}
elsif ( $symbols_txt eq 'natural' ) {
    $symbols = $cfg->symbols->natural;
}
elsif ( $symbols_txt eq 'synthetics' ) {
    $symbols = $cfg->symbols->synthetic;
}
else {
    $symbols = [ split( ',', $symbols_txt ) ] if ($symbols_txt);
}

my $timeframes = [604800];
$timeframes = [ split( ',', $timeframes_txt ) ] if ($timeframes_txt);

foreach my $symbol ( @{$symbols} ) {
    foreach my $tf ( @{$timeframes} ) {

        print qq /TRUNCATE TABLE `$symbol\_$tf`;
/;

    }
}
