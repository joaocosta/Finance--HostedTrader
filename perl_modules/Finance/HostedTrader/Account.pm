package Finance::HostedTrader::Account;
=head1 NAME

    Finance::HostedTrader::Account - Trade object

=head1 SYNOPSIS

    use Finance::HostedTrader::Account;
    my $obj = Finance::HostedTrader::Account->new(
                );

=head1 DESCRIPTION


=head2 METHODS


=cut


use strict;
use warnings;
use Moose;
use Finance::HostedTrader::ExpressionParser;
use Finance::HostedTrader::Position;


use YAML::Syck;
use Data::Dumper;

YAML::Syck->VERSION( '0.70' );


##These should exist everywhere, regardless of broker
#
#=item C<username>
#
#
#=cut
#has username => (
#    is     => 'ro',
#    isa    => 'Str',
#    required=>0,
#);
#
#=item C<password>
#
#
#=cut
#has password => (
#    is     => 'ro',
#    isa    => 'Str',
#    required=>0,
#);
#
sub BUILD {
    my $self = shift;

    $self->{_signal_processor} = Finance::HostedTrader::ExpressionParser->new();
    $self->{_positions} = {};
}

=head3 Must be overriden

=over 12


=item C<refreshPositions()>

Must update $self->{_positions} with an hash ref keyed by symbol with a L<Finance::HostedTrader::Position> object as value.

This method will typically have to read existing positions from the Account provider (eg: L<Finance::HostedTrader::Account::FXCM>)
and store them in the Account object for local access.

It gets called by getPosition and getPositions


=cut
sub refreshPositions {
    die("overrideme");
}

=item C<getSymbolBase($symbol)>

Returns the base currency for a symbol, useful for calculating profit/loss.

Eg:
 US Stocks => 'USD'
 EURUSD => 'USD'
 USDCHF => 'CHF'

=cut
sub getSymbolBase {
    die("overrideme");
}

=item C<getAsk($symbol)>

Return the current ask price for $symbol.

=cut
sub getAsk {
    die("overrideme");
}

=item C<getBid>

Return the current bid price for $symbol.

=cut
sub getBid {
    die("overrideme");
}

=item C<openMarket($symbol, $direction, $amount>

Opens a trade in $symbol at current market price.

$direction can be either 'long' or 'short'

Returns a list containing two elements:

$tradeID - This can be passed to closeMarket. It can also be retrieved via getTrades
$price   - The price at which the trade was executed.

=cut

sub openMarket {
    die("overrideme");
}

=item C<closeMarket($tradeID, $amount)>

Closes a trade at current market price.

$tradeID is returned when calling openMarket(). It can also be retrieved via getTrades().

Returns $closedTradeID

=cut
sub closeMarket {
    die("overrideme");
}

=item C<getBaseUnit($symbol)>

Returns the base unit at which the symbol trades.
Eg, if baseUnit=10000, the symbol can only trade in multiples of 10000 (15000 would be an invalid trade size).

=cut
sub getBaseUnit {
    die("overrideme");
}

=item C<getNav()>

Return the current net asset value in the account

=cut
sub getNav {
    die("overrideme");
}

=item C<getBaseCurrency()>

Returns the currency in which funds are held in this account. Useful to calculate profit/loss.

=cut
sub getBaseCurrency {
    die("overrideme");
}

=back

=head3 Implemented methods

=over 12

=item C<checkSignal($symbol, $signal, $args)>

Returns true if the given $signal/$args occurs in $symbol

=cut
sub checkSignal {
    my ($self, $symbol, $signal_definition, $signal_args) = @_;

    return $self->{_signal_processor}->checkSignal(
        {
            'expr' => $signal_definition, 
            'symbol' => $symbol,
            'tf' => $signal_args->{timeframe},
            'maxLoadedItems' => $signal_args->{maxLoadedItems},
            'period' => $signal_args->{period},
            'debug' => $signal_args->{debug},
        }
    );
}

=item C<getIndicatorValue($symbol, $indicator, $args)

Returns the indicator value of $indicator/$args on $symbol.

=cut
sub getIndicatorValue {
    my ($self, $symbol, $indicator, $args) = @_;

    my $value = $self->{_signal_processor}->getIndicatorData( {
                symbol  => $symbol,
                tf      => $args->{timeframe},
                fields  => 'datetime, ' . $indicator,
                maxLoadedItems => $args->{maxLoadedItems},
                numItems => 1,
                debug => $args->{debug},
    } );

    return $value->[0]->[1];
}

=item C<waitForNextTrades($system)>

Sleeps for 20 seconds. $system is ignored.

This method is called by Trader.pl and is overriden by C<Finance::HostedTrader::Account::UnitTest>.
It probably doesn't belong in the Account object.

=cut
sub waitForNextTrade {
    my ($self, $system) = @_;

    sleep(20);
}

=item C<converToBaseCurrency($amount, $currentCurrency, $bidask>

Converts $amount from $currentCurrency to the account's base currency, using either 'bid' or 'ask' price.

=cut

sub convertToBaseCurrency {
    my ($self, $amount, $currentCurrency, $bidask) = @_;
    $bidask = 'ask' if (!$bidask);

    my $baseCurrency = $self->getBaseCurrency();

    return $amount if ($baseCurrency eq $currentCurrency);
    my $pair = $baseCurrency . $currentCurrency;
    if ($bidask eq 'ask') {
        return $amount / $self->getAsk($pair);
    } elsif ($bidask eq 'bid') {
        return $amount / $self->getBid($pair);
    } else {
        die("Invalid value in bidask argument: '$bidask'");
    }
}

=item C<convertBaseUnit($symbol, $amount)>

Convert $amount to the base unit supported by $symbol.

See the getBaseUnit method.

=cut
sub convertBaseUnit {
    my ($self, $symbol, $amount) = @_;
    my $baseUnit = $self->getBaseUnit($symbol);

    return int($amount / $baseUnit) * $baseUnit;
}

=item C<getPosition($symbol)>

Returns a C<Finance::HostedTrader::Position> object for $symbol.

This object will contain information about all open trades in $symbol.

=cut
sub getPosition {
    my ($self, $symbol) = @_;

    $self->refreshPositions();
    my $positions = $self->{_positions};
    return $positions->{$symbol} || Finance::HostedTrader::Position->new(symbol=>$symbol);
}

=item C<getPositions()>

Returns a hashref whose key is a symbol and value a C<Finance::HostedTrader::Position> object for that symbol.
=cut
sub getPositions {
    my ($self) = @_;

    $self->refreshPositions();
    return $self->{_positions};
}

=item C<closeTrades($symbol,$direction)>

Closes all trades in the given $symbol/$direction at market values.

=cut
sub closeTrades {
    my ($self, $symbol, $direction) = @_;

    my $position = $self->getPosition($symbol);
    foreach my $trade (@{ $position->trades }) {
        next if ($trade->direction ne $direction);
        $self->closeMarket($trade->id, $trade->size);
    }
}


__PACKAGE__->meta->make_immutable;
1;

=back


=head1 LICENSE

This is released under the MIT license. See L<http://www.opensource.org/licenses/mit-license.php>.

=head1 AUTHOR

Joao Costa - L<http://zonalivre.org/>

=head1 SEE ALSO

L<Finance::HostedTrader::Factory::Account>
L<Finance::HostedTrader::Position>

=cut
