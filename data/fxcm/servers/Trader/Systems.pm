package Systems;

use strict;
use warnings;

use FXCMServer;
use Finance::HostedTrader::ExpressionParser;


use Moose;
use Config::Any;
use Date::Manip;
use YAML::Tiny;

has 'name' => (
    is     => 'ro',
    isa    => 'Str',
    required=>1,
);

sub BUILD {
    my $self = shift;

    $self-> _loadSystem();
    $self->{_signal_processor} = Finance::HostedTrader::ExpressionParser->new();
    $self->{_system}->{symbols} = $self->_loadSymbols();
}

sub data {
    my $self = shift;
    return $self->{_system};
}

sub updateSymbols {
    my $self = shift;
    my $newSymbols = shift || die("No new symbols specified");

    my $trades = _getCurrentTrades();
    my $symbols = $self->_loadSymbols();#$self->{_system}->{symbols};
    #List of symbols for which there are open short positions
    my @symbols_to_keep_short = map {$_->{symbol}} grep {$_->{direction} eq 'short'} @{$trades}; 
    #List of symbols for which there are open long positions
    my @symbols_to_keep_long = map {$_->{symbol}} grep {$_->{direction} eq 'long'} @{$trades};

    #Add symbols for which there are existing positions to the list
    #If these are not kept in the trade list, open positions in these symbols will 
    #not be closed by the system
    $symbols->{short} = \@symbols_to_keep_short;
    $symbols->{long} = \@symbols_to_keep_long;
    use Data::Dumper;
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

    return $self->_checkSignal($signal_definition->{signal}, $symbol, $tradeDirection, $signal_definition->{timeframe}, $signal_definition->{maxLoadedItems});
}

sub _checkSignal {
    my ($self, $expr, $symbol, $direction, $timeframe, $maxLoadedItems) = @_;
#    logger("Signal $expr");
#    Hardcoded -1hour, means check signals ocurring in the last hour
#    would be better to use the date of the last signal instead
    my $startPeriod = UnixDate(DateCalc('now', '- 1hour'), '%Y-%m-%d %H:%M:%S');
    my $data = $self->{_signal_processor}->getSignalData(
        {
            'expr'            => $expr,
            'symbol'          => $symbol,
            'tf'              => $timeframe,
            'maxLoadedItems'  => $maxLoadedItems,
            'startPeriod'     => $startPeriod,
            'numItems'        => 1,
            'debug'           => 0,
        }
    );

    return $data->[0] if defined($data);
    return undef;
}

sub _loadSystem {
    my $self = shift;

    my $file = "systems/".$self->name.".yml";
    my $system = Config::Any->load_files(
        {
            files => [$file],
            use_ext => 1,
            flatten_to_hash => 1,
        }
    );

    die("failed to load system from $file. $!") unless defined($system);
    die("invalid name in symbol file $file") if ($self->name ne $system->{$file}->{name});
    $self->{_system} = $system->{$file};
}

sub _getCurrentTrades {
#Call FXCMServer from limited scope
#so that we release the TCP connection
#to the single threaded server
#as soon as possible
# TODO this code should be agnostic to FXCMServer, instead should be using Finance::HostedTrader::Account
my $s = FXCMServer->new();

return $s->getTrades();
}


__PACKAGE__->meta->make_immutable;
1;
