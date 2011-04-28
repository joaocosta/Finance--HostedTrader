#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Text::ASCIITable;
use HTML::Table;
use Params::Validate qw(:all);

use Finance::HostedTrader::Factory::Account;
use Finance::HostedTrader::Systems;

my ($address, $port, $class, $format) = ('127.0.0.1', 1500, 'FXCM', 'text');

GetOptions(
    "class=s"   => \$class,
    "address=s" => \$address,
    "port=i"    => \$port,
    "format=s"  => \$format,
);

sub table_factory {
    my %args = validate( @_, {
        format          => 1,
        headingText    => { type => SCALAR, default => undef },
        cols            => { type => ARRAYREF }
    });

    my $t;

    if ($args{format} eq 'text') {
        require Text::ASCIITable;
        $t = Text::ASCIITable->new( { headingText => $args{headingText} } );
        $t->setCols(@{ $args{cols}} );
    } elsif ($args{format} eq 'html') {
    } else {
        die("unknown format: $args{format}");
    }

    return $t;
}

my $account = Finance::HostedTrader::Factory::Account->new( SUBCLASS => $class, address => $address, port => $port)->create_instance();

#my $account = Finance::HostedTrader::Account::FXCM->new(
#                address => $address,
#                port => $port,
#              );

my $trades = [];#$account->getTrades();
my $nav = $account->getNav();




my $system = Finance::HostedTrader::Systems->new( name => 'trendfollow', account => $account );

my $positions = $account->getPositions();

my $t = table_factory( format=> 'text', headingText => 'Open Positions', cols => ['Symbol', 'Open Date','Size','Entry','Current','PL','%'] );

my $h = HTML::Table->new(
        -head => ['Symbol', 'Open Date','Size','Entry','Current','PL','%'],
        );

foreach my $symbol (keys %$positions) {
my $position = $positions->{$symbol};

foreach my $trade (@{ $position->trades }) {
    my $stopLoss = $system->getExitValue($trade->symbol, $trade->direction);
    my $marketPrice = ($trade->direction eq 'short' ? $account->getAsk($trade->symbol) : $account->getBid($trade->symbol));
    my $baseCurrencyPL = $trade->pl;
    my $percentPL = sprintf "%.2f", 100 * $baseCurrencyPL / $nav;

    $t->addRow(
        $trade->symbol,
        $trade->openDate,
        $trade->size,
        $trade->openPrice,
        $marketPrice,
        sprintf('%.2f', $baseCurrencyPL),
        $percentPL
    );
    $h->addRow(
        $trade->symbol,
        $trade->openDate,
        $trade->size,
        $trade->openPrice,
        $marketPrice,
        sprintf('%.2f', $baseCurrencyPL),
        $percentPL
    );
}
}

print "ACCOUNT NAV: " . $nav . "\n\n";
print $t;

print "\n";


foreach my $system_name ( qw/trendfollow/ ) {
    my $t = table_factory( format => 'text', headingText => $system_name, cols => ['Symbol','Market','Entry','Exit','Direction', 'Worst Case', '%']);
    my $h = HTML::Table->new(
        -head => ['Symbol','Market','Entry','Exit','Direction', 'Worst Case', '%'],
        );
    my $system = Finance::HostedTrader::Systems->new( name => $system_name, account => $account );
    my $data = $system->data;
    my $symbols = $data->{symbols};

    foreach my $direction (qw /long short/) {
        foreach my $symbol (@{$symbols->{$direction}}) {
            my $currentExit = $system->getExitValue($symbol, $direction);
            my $currentEntry = $system->getEntryValue($symbol, $direction);
            my $positionRisk = -1*$system->positionRisk($account->getPosition($symbol));

            $t->addRow( $symbol, 
                        ($direction eq 'long' ? $account->getAsk($symbol) : $account->getBid($symbol)),
                        $currentEntry,
                        $currentExit,
                        $direction,
                        sprintf('%.2f',$positionRisk),
                        sprintf('%.2f',100 * $positionRisk / $nav)
            );

            $h->addRow( $symbol, 
                        ($direction eq 'long' ? $account->getAsk($symbol) : $account->getBid($symbol)),
                        $currentEntry,
                        $currentExit,
                        $direction,
                        sprintf('%.2f',$positionRisk),
                        sprintf('%.2f',100 * $positionRisk / $nav)
            );

        }
    }
    print $t;
}










####OLD - Simpler and faster but less generic
=pod
use Finance::HostedTrader::ExpressionParser;

sub _getSymbolsTrendFollow {
    my $symbols = getAllSymbols();
    my @results;
    my $processor   = Finance::HostedTrader::ExpressionParser->new();

    my $rv = { long => [], short => [] };

    foreach my $symbol (@$symbols) {
        my $data = $processor->getIndicatorData( {
            'fields'          => "datetime,abs(trend(close,21)),trend(close,21)",
            'symbol'        => $symbol,
            'tf'            => 'week',
            'maxLoadedItems'=> 41,
            'numItems'      => 1,
            'debug'         => 0,
        });
        $data = $data->[0];
        push @results, [ $symbol, ($data->[2] > 0 ? 'long' : 'short'), $data->[1] ] if ($data->[1] > 1);
    }

    my @sorted = sort { $b->[2] <=> $a->[2] } @results ;
    splice @sorted, 5;

    foreach my $item (@sorted) {
        push @{ $rv->{long} }, $item->[0] if ($item->[1] eq 'long');
        push @{ $rv->{short} }, $item->[0] if ($item->[1] eq 'short');
    }
    return $rv;
}
=cut
