#!/usr/bin/perl

use strict;
use warnings;
$| = 1;
#use Proc::Daemon;
#Proc::Daemon::Init;
use Getopt::Long;
use Data::Dumper;
use Date::Manip;
use Pod::Usage;


use Finance::HostedTrader::Factory::Account;
use Finance::HostedTrader::Systems;

my ($verbose, $help, $address, $port, $class) = (0, 0, '127.0.0.1', 1500, 'FXCM');

my $result = GetOptions(
    "class=s",  \$class,
    "address=s",\$address,
    "port=i",   \$port,
    "verbose",  \$verbose,
    "help",     \$help,
    "startDate",\$startDate,
    "endDate",  \$endDate,
) || pod2usage(2);

pod2usage(1) if ($help);

logger("STARTUP");

my $account = Finance::HostedTrader::Factory::Account->new( SUBCLASS => $class, address => $address, port => $port)->create_instance();

my @systems =   (   
                    Finance::HostedTrader::Systems->new( name => 'trendfollow', account => $account ),
                );

foreach my $system (@systems) {
    logger("Loaded system " . $system->{name});
}

my $debug = 0;
my $symbolsLastUpdated = 0;
while (1) {
    logger("Time is:" . $account->{_now}) if ($class eq 'UnitTest');
    foreach my $system (@systems) {
# Applies system filters and updates list of symbols traded by this system
# Updates symbol list every 15 minutes
        if ( time() - $system->symbolsLastUpdated() > 900 ) {
            if ($verbose) {
                my $symbols_long = $system->symbols('long');
                my $symbols_short = $system->symbols('short');
                logger("Current symbol list");
                logger("long: " . join(',', @$symbols_long));
                logger("short: " . join(',', @$symbols_short));
            }
            $system->updateSymbols();
            if ($verbose) {
                my $symbols_long = $system->symbols('long');
                my $symbols_short = $system->symbols('short');
                logger("Updated symbol list");
                logger("long: " . join(',', @$symbols_long));
                logger("short: " . join(',', @$symbols_short));
            }

        }
        eval {
            checkSystem($account, $system, 'long');
            1;
        } or do {
            logger($@);
        };

        eval {
            checkSystem($account, $system, 'short');
            1;
        } or do {
            logger($@);
        };
    }
    $account->waitForNextTrade();
    last if ( $class eq 'UnitTest' && $account->{_now} gt UnixDate($account->endDate, '%Y-%m-%d %H:%M:%S') );
}

print Dumper(\$account);

sub checkSystem {
    my ($account, $system, $direction) = @_;

    my $symbols = $system->symbols($direction);

    foreach my $symbol ( @$symbols ) {
        my $position = $account->getPosition($symbol);
        my $posSize = $position->size;
        my $numOpenTrades = scalar(@{$position->trades});

        if ($numOpenTrades < $system->maxNumberTrades) {
            logger("Checking ".$system->name." $symbol $direction") if ($verbose);
            my $result = $system->checkEntrySignal($symbol, $direction);
            if ($result) {
                my ($amount, $value, $stopLoss) = $system->getTradeSize($symbol, $direction, $position);
                if ($verbose && $result) {
                    logger("Signal detected: " . $result->[0]);
                }
                next if ($amount <= 0);
                logger("Adding position for $symbol $direction ($amount)");

                TRY_OPENTRADE: foreach my $try (1..3) {
                    eval {
                        my ($orderID, $rate) = $account->openMarket($symbol, $direction, $amount);
                        logger("symbol=$symbol,direction=$direction,amount=$amount,orderID=$orderID,rate=$rate");
                        1;
                    } or do {
                        logger($@);
                        next;
                    };
                    sendMail('Trading Robot - Open Trade ' . $symbol, qq {Open Trade:
Instrument: $symbol
Direction: $direction
Amount: $amount
Current Value: $value
Stop Loss: $stopLoss
                });
                    last TRY_OPENTRADE;
                }
            }
        }

        if ($posSize) {
            my $result = $system->checkExitSignal($symbol, $direction);
            if ($result) {
                logger("Closing position for $symbol $direction ( $posSize )");
                $account->closeTrades($symbol, $direction);
                my $value;
                if ($direction eq "long") {
                    $value = $account->getAsk($symbol);
                } else {
                    $value = $account->getBid($symbol);
                }
                sendMail('Trading Robot - Close Trade ' . $symbol, qq {Close Trade:
Instrument: $symbol
Direction: $direction
Position Size: $posSize
Current Value: $value
                });
            }
        }
    }
}

sub logger {
    my $msg = shift;

    my $datetimeNow = UnixDate('now', '%Y-%m-%d %H:%M:%S');
    print "[$datetimeNow] $msg\n";
}


sub sendMail {
my ($subject, $content) = @_;
use MIME::Lite;

    return if ($class eq 'UnitTest');
    logger($content);
    ### Create a new single-part message, to send a GIF file:
    my $msg = MIME::Lite->new(
        From     => 'fxhistor@fxhistoricaldata.com',
        To       => 'joaocosta@zonalivre.org',
        Subject  => $subject,
        Data     => $content
    );
    $msg->send; # send via default
}
