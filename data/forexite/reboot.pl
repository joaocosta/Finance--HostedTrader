#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Finance::HostedTrader::Config;
use Data::Dumper;



my $cfg = Finance::HostedTrader::Config->new();


doAll($cfg->symbols->synthetic, $cfg->timeframes->all);
doAll($cfg->symbols->all, $cfg->timeframes->synthetic);

sub doAll {
my ($symbols, $timeframes) = @_;
foreach my $symbol ( @{$symbols} ) {
    foreach my $tf ( @{$timeframes} ) {
        print qq /TRUNCATE TABLE `$symbol\_$tf`;
/;
    }
}
}

=pod
fx-update-tf.pl --verbose --available-timeframe=60 --timeframes=300
fx-update-tf.pl --verbose --available-timeframe=300 --timeframes=900,1800,3600
fx-update-tf.pl --verbose --available-timeframe=3600 --timeframes=7200,14400,86400
fx-update-tf.pl --verbose --available-timeframe=86400 --timeframes=604800
=cut
