package Systems;

use strict;
use warnings;

use Finance::HostedTrader::Config;


use Moose;
use Config::Any;
use YAML::Tiny;
use List::Compare::Functional qw( get_intersection );
use Hash::Merge;

has 'name' => (
    is     => 'ro',
    isa    => 'Str',
    required=>1,
);

has 'account' => (
    is     => 'ro',
    isa    => 'Finance::HostedTrader::Account',
    required=>1,
);

sub BUILD {
    my $self = shift;

    $self-> _loadSystem();
    $self->{_system}->{symbols} = $self->_loadSymbols();
    $self->{_symbolsLastUpdated} = 0;
}

sub data {
    my $self = shift;
    return $self->{_system};
}

sub symbolsLastUpdated {
    my $self = shift;

    return $self->{_symbolsLastUpdated};
}

sub updateSymbols {
    my $self = shift;
    my $account = $self->account;

    my $newSymbols = $self->getSymbolsSignalFilter($self->{_system}->{filters});
    my $trades = $account->getTrades();
    my $symbols = $self->_loadSymbols();#$self->{_system}->{symbols};
    #List of symbols for which there are open short positions
    my @symbols_to_keep_short = map {$_->{symbol}} grep {$_->{direction} eq 'short'} @{$trades}; 
    #List of symbols for which there are open long positions
    my @symbols_to_keep_long = map {$_->{symbol}} grep {$_->{direction} eq 'long'} @{$trades};

    #Add symbols for which there are existing positions to the list
    #If these are not kept in the trade list, open positions in these symbols will 
    #not be closed by the system
    #Only keep open trades if they were originally in this list already, otherwise the symbols were input by a different system instance
    $symbols->{short} = [ get_intersection('--unsorted', [ \@symbols_to_keep_short, $symbols->{short} ] ) ];
    $symbols->{long} = [ get_intersection('--unsorted', [ \@symbols_to_keep_long, $symbols->{long} ] ) ];

    #Now add to the trade list symbols triggered by the system as trade opportunities
    foreach my $tradeDirection (qw /long short/ ) {
    foreach my $symbol ( @{$newSymbols->{$tradeDirection}} ) {
        #Don't add a symbol if it already exists in the list (avoid duplicates)
        next if (grep {/$symbol/} @{ $symbols->{$tradeDirection} });
        push @{ $symbols->{$tradeDirection} }, $symbol;
    }
    }

    my $yml = YAML::Tiny->new;
    $yml->[0] = { name => $self->name, symbols => $symbols};
    my $file = $self->_getSymbolFileName();
    $yml->write($file) || die("Failed to write symbols file $file. $!");
    $self->{_system}->{symbols} = $symbols;
    $self->{_symbolsLastUpdated} = time();
}

#Return list of symbols to add to the system
sub getSymbolsSignalFilter {
    my $self = shift;
    my $filters = shift;

    my $long_symbols = $filters->{symbols}->{long};
    my $short_symbols = $filters->{symbols}->{short};
    my $account = $self->account;

    my $rv = { long => [], short => [] };

    my $filter=$filters->{signals}->[0];

    foreach my $symbol (@$long_symbols) {
        if ($account->checkSignal(
                $symbol,
                $filter->{longSignal},
                $filter->{args}
        )) {
            push @{ $rv->{long} }, $symbol;
        }
    }

    foreach my $symbol (@$short_symbols) {
        if ($account->checkSignal( {
            $symbol,
            $filter->{shortSignal},
            $filter->{args},
        })) {
            push @{ $rv->{short} }, $symbol;
        }
    }

    return $rv;
}

sub _getSymbolFileName {
    my ($self) = @_;

    return 'systems/'.$self->name.'.symbols.yml';
}

sub _loadSymbols {
    my $self = shift;
    my $file = $self->_getSymbolFileName;

    my $yaml = YAML::Tiny->new;
    $yaml = YAML::Tiny->read( $file ) || die("Cannot read symbols from $file. $!");

    die("invalid name in symbol file $file") if ($self->name ne $yaml->[0]->{name});

    return $yaml->[0]->{symbols};
}

sub getEntryValue {
    my $self = shift;

    return $self->_getSignalValue('enter', @_);
}

sub getExitValue {
    my $self = shift;

    return $self->_getSignalValue('exit', @_);
}

sub _getSignalValue {
    my ($self, $action, $symbol, $tradeDirection) = @_;

    my $signal = $self->{_system}->{signals}->{$action};

    return $self->account->getIndicatorValue(
                $symbol, 
                $signal->{$tradeDirection}->{currentPoint},
                $signal->{args}
    );
}

sub checkEntrySignal {
    my $self = shift;

    return $self->_checkSignalWithAction('enter', @_);
}

sub checkExitSignal {
    my $self = shift;

    return $self->_checkSignalWithAction('exit', @_);
}

sub _checkSignalWithAction {
    my ($self, $action, $symbol, $tradeDirection) = @_;

    my $signal_definition = $self->{_system}->{signals}->{$action}->{$tradeDirection};
    my $signal_args = $self->{_system}->{signals}->{$action}->{args};

    return $self->account->checkSignal(
                    $symbol,
                    $signal_definition->{signal},
                    $signal_args
    );
}

sub _loadSystem {
    my $self = shift;

    my $file = "systems/".$self->name.".tradeable.yml";
    my $tradeable_filter = "systems/".$self->name.".yml";
    my @files = ($file, $tradeable_filter);
    my $system_all = Config::Any->load_files(
        {
            files => \@files,
            use_ext => 1,
            flatten_to_hash => 1,
        }
    );
    my $system = {};

	my $merge = Hash::Merge->new('custom_merge'); #The custom_merge behaviour is defined in Finance::HostedTrader::Config
    foreach my $file (@files) {
        next unless ( $system_all->{$file} );
        my $new_system = $merge->merge($system_all->{$file}, $system);
        $system=$new_system;
    }

    die("failed to load system from $file. $!") unless defined($system_all);
    die("invalid name in symbol file $file") if ($self->name ne $system->{name});
    $self->{_system} = $system;
}

sub maxNumberTrades {
my ($self) = @_;

my $exposurePerPosition = $self->{_system}->{maxExposure};
die("no exposure coefficients in system definition") if (!$exposurePerPosition || !scalar(@{$exposurePerPosition}));
return scalar(@{$exposurePerPosition});
}

sub getTradeSize {
my $self = shift;
my $symbol = shift;
my $direction = shift;
my $position = shift;

my $maxLossPts;
my $system = $self->{_system};
my $trades = $position->trades;
my $account = $self->account;


    my $exposurePerPosition = $system->{maxExposure};
    die("no exposure coefficients in system definition") if (!$exposurePerPosition || !scalar(@{$exposurePerPosition}));
    return (0,undef,undef) if (scalar(@$trades) >= scalar(@{$exposurePerPosition}));

    my $maxExposure = $exposurePerPosition->[@{$trades}];
    die("max exposure is negative") if ($maxExposure <0);
    my $nav = $account->getNav();
    die("nav is negative") if ($nav < 0);

    my $maxLoss   = $nav * $maxExposure / 100;
    my $stopLoss = $self->_getSignalValue('exit', $symbol, $direction);
    my $base = uc(substr($symbol, -3));

    if ($base ne "GBP") { # TODO: should not be hardcoded that account is based on GBP
        $maxLoss *= $account->getAsk("GBP$base");
    }

    my $value;
    if ($direction eq "long") {
        $value = $account->getAsk($symbol);
        $maxLossPts = $value - $stopLoss;
    } else {
        $value = $account->getBid($symbol);
        $maxLossPts = $stopLoss - $value;
    }

    if ( $maxLossPts <= 0 ) {
        die("Tried to set stop to " . $stopLoss . " but current price is " . $value);
    }
    my $amount = $account->convertBaseUnit($symbol, $maxLoss / $maxLossPts);
    $amount -= $position->size;
    $amount = 0 if ($amount < 0);
    return ($amount, $value, $stopLoss);
}

sub symbols {
    my ($self, $direction) = @_;

    return $self->{_system}->{symbols}->{$direction};
}


__PACKAGE__->meta->make_immutable;
1;
