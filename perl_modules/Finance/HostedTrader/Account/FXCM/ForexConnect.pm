package Finance::HostedTrader::Account::FXCM::ForexConnect;
=head1 NAME

    Finance::HostedTrader::Account::FXCM::ForexConnect - Interface to the FXCM broker

=head1 SYNOPSIS

    use FXCM;
    my $s = Finance::HostedTrader::Account::FXCM::ForexConnect->new( username => '', password => '', accountType => 'Real' );
    print $s->getAsk('EURUSD');
    print $s->getBid('EURUSD');

    my ($openOrderID, $price) = $s->openMarket('EURUSD', 'long', 100000);
    my $trades = $s->getTrades();

    my $tradeID = $trades->[0]->{ID};
    my $closeOrderID = $s->closeMarket($tradeID, 100000);

=head1 DESCRIPTION

Interfaces with the FXCM ForexConnect API.
The Order2GO API is available as a Java binding.

=head2 Properties

=over 12

=cut

use Moose;
extends 'Finance::HostedTrader::Account';

use Inline  Java    => 'STUDY',
            STUDY   => [ qw(org.zonalivre.ForexConnect) ],
            AUTOSTUDY=> 1;

use Moose::Util::TypeConstraints;
use YAML::Syck;
use Finance::HostedTrader::Trade;

=back

=head2 Methods

=over 12

=cut

=item C<username>

Account username

=cut
has username => (
    is      => 'ro',
    isa     => 'Str',
    required=> 1,
);

=item C<password>

Account password

=cut
has password => (
    is      => 'ro',
    isa     => 'Str',
    required=> 1,
);

=item C<accountType>


=cut
enum 'FXCMOrder2GOAccountType' => qw(Demo Real);
has accountType => (
    is     => 'ro',
    isa    => 'FXCMOrder2GOAccountType',
    required=>1,
);

=item <notifier>
=cut
has notifier => (
    is     => 'ro',
    isa    => 'Maybe[Finance::HostedTrader::Trader::Notifier]',
    required=>1,
    default=> sub {
                    my $self = shift;
                    require Finance::HostedTrader::Trader::Notifier::Production;
                    return Finance::HostedTrader::Trader::Notifier::Production->new();
                  },
);


my %symbolMap = (
    AUDCAD => 'AUD/CAD',
    AUDCHF => 'AUD/CHF',
    AUDJPY => 'AUD/JPY',
    AUDNZD => 'AUD/NZD',
    AUDUSD => 'AUD/USD',
    AUS200 => 'AUS200',
    CADCHF => 'CAD/CHF',
    CADJPY => 'CAD/JPY',
    CHFJPY => 'CHF/JPY',
    CHFNOK => 'CHF/NOK',
    CHFSEK => 'CHF/SEK',
    EURAUD => 'EUR/AUD',
    EURCAD => 'EUR/CAD',
    EURCHF => 'EUR/CHF',
    EURDKK => 'EUR/DKK',
    EURGBP => 'EUR/GBP',
    EURJPY => 'EUR/JPY',
    EURNOK => 'EUR/NOK',
    EURNZD => 'EUR/NZD',
    EURSEK => 'EUR/SEK',
    EURTRY => 'EUR/TRY',
    EURUSD => 'EUR/USD',
    GBPAUD => 'GBP/AUD',
    GBPCAD => 'GBP/CAD',
    GBPCHF => 'GBP/CHF',
    GBPJPY => 'GBP/JPY',
    GBPNZD => 'GBP/NZD',
    GBPSEK => 'GBP/SEK',
    GBPUSD => 'GBP/USD',
    HKDJPY => 'HKD/JPY',
    NOKJPY => 'NOK/JPY',
    NZDCAD => 'NZD/CAD',
    NZDCHF => 'NZD/CHF',
    NZDJPY => 'NZD/JPY',
    NZDUSD => 'NZD/USD',
    SEKJPY => 'SEK/JPY',
    SGDJPY => 'SGD/JPY',
    TRYJPY => 'TRY/JPY',
    USDCAD => 'USD/CAD',
    USDCHF => 'USD/CHF',
    USDDKK => 'USD/DKK',
    USDHKD => 'USD/HKD',
    USDJPY => 'USD/JPY',
    USDMXN => 'USD/MXN',
    USDNOK => 'USD/NOK',
    USDSEK => 'USD/SEK',
    USDSGD => 'USD/SGD',
    USDTRY => 'USD/TRY',
    USDZAR => 'USD/ZAR',
    XAGUSD => 'XAG/USD',
    XAUUSD => 'XAU/USD',
    ZARJPY => 'ZAR/JPY',
    ESP35  => 'ESP35',
    FRA40  => 'FRA40',
    GER30  => 'GER30',
    HKG33  => 'HKG33',
    ITA40  => 'ITA40',
    JPN225 => 'JPN225',
    NAS100 => 'NAS100',
    SPX500 => 'SPX500',
    SUI30  => 'SUI30',
    SWE30  => 'SWE30',
    UK100  => 'UK100',
    UKOil  => 'UKOil',
    US30   => 'US30',
    USOil  => 'USOil',
);

sub BUILD {
    my $self = shift;

    $self->{_fx} = Finance::HostedTrader::Account::FXCM::ForexConnect::org::zonalivre::ForexConnect->new($self->username, $self->password, $self->accountType);
}

=item C<refreshPositions()>


=cut
sub refreshPositions {
    my ($self) = @_;

    $self->{_positions} = {};
    my $yml = $self->{_fx}->getTrades();

    return if (!$yml);
    my $trades = YAML::Syck::Load( $yml );
    die("Invalid yaml: $!") if (!$trades);

    foreach my $trade_data (@$trades) {
        $trade_data->{symbol} =~ s|/||;
        if ($trade_data->{direction} eq 'short') {
            #FXCM returns short positions as positive numbers,
            #convert to negative
            $trade_data->{size} *= -1;
        }
        my $trade = Finance::HostedTrader::Trade->new(
            $trade_data
        );
        my $trade_symbol = $trade->symbol;

        if (!exists($self->{_positions}->{$trade_symbol})) {
            $self->{_positions}->{$trade->symbol} = Finance::HostedTrader::Position->new(symbol => $trade_symbol);
        }
        $self->{_positions}->{$trade->symbol}->addTrade($trade);
    }
}

=item C<getAsk($symbol)>

Returns the current ask(long) price for $symbol

=cut

sub getAsk {
    my ($self, $symbol) = @_;

    $symbol = $self->_convertSymbolToFXCM($symbol);
    return $self->{_fx}->getAsk($symbol);
}

=item C<getBid($symbol)>

Returns the current bid(short) price for $symbol

=cut

sub getBid {
    my ($self, $symbol) = @_;

    $symbol = $self->_convertSymbolToFXCM($symbol);
    return $self->{_fx}->getBid($symbol);
}

=item C<openMarket($symbol, $direction, $amount>

Opens a trade in $symbol at current market price.

$direction can be either 'long' or 'short'

In FXCM, $amount needs to be a multiple of 10.000

Returns a list containing two elements:

$tradeID - This can be passed to closeMarket. It can also be retrieved via getTrades
$price   - The price at which the trade was executed.

=cut

augment 'openMarket' => sub {
    my ($self, $symbol, $direction, $amount, $stopLoss) = @_;

    my $fxcm_symbol = $self->_convertSymbolToFXCM($symbol);
    my $fxcm_direction = ($direction eq 'long' ? 'B' : 'S');
    my $data;

    #the openmarket call can fail if price moves
    #to quickly, so try it 3 times until it succeeds
    TRY_OPENTRADE: foreach my $try (1..3) {
        eval {
            $data = $self->{_fx}->openMarket($fxcm_symbol,$fxcm_direction,$amount);
            1;
        } or do {
            #TODO would be preferable to log something here
            next;
        };
        last TRY_OPENTRADE;
    }
    my ($orderID, $rate) = split(/ /, $data); #TODO don't need to return rate here

    #Try to fetch the trade object for the trade just opened
    #Try up to 5 times because getPosition implicitly sends a call to the FXCM API to retrieve existing
    #trades which usually doesn't imediatelly return the open trade 
    my $tries = 5;
    while ($tries--) {
        my $trade = $self->getPosition($symbol)->getTrade($orderID);
        return $trade if (defined($trade));
        sleep(1); #Sleep a bit because FXCM server may not imediatelly return the trade just opened #TODO use Zefram's module and sleep less time
    }
    die("Could not find trade just opened. Return from _sendCmd was: '$data'");
};

=item C<closeMarket($tradeID, $amount)>

Closes a trade at current market price.

$tradeID is returned when calling openMarket(). It can also be retrieved via getTrades().

Returns $closedTradeID

=cut

sub closeMarket {
    my ($self, $tradeID, $amount) = @_;

    return $self->{_fx}->closeMarket($tradeID,$amount);
}

=item C<getBaseUnit($symbol)>

Returns the base unit at which the symbol trades.

In FXCM, most symbols trade at multiples of 10.000, but some will vary ( XAGUSD uses multiples of 50 ).
=cut

sub getBaseUnit {
    my ($self, $symbol) = @_;

    $symbol = $self->_convertSymbolToFXCM($symbol);
    return $self->_sendCmd("baseunit $symbol");
}

=item C<getNav()>

Return the current net asset value in the account

=cut

sub getNav {
    my ($self) = @_;

    return $self->{_fx}->getNav;
}

=item C<getBaseCurrency>

=cut
sub getBaseCurrency {
    my ($self) = @_;
    return 'GBP'; #TODO

}

sub _convertSymbolToFXCM {
    my ($self, $symbol) = @_;

    die("Unsupported symbol '$symbol'") if (!exists($symbolMap{$symbol}));
    return $symbolMap{$symbol};
}


sub _sendCmd {
    my ($self, $cmd) = @_;

    die($cmd . ' not implemented');
}

sub getServerEpoch {
    my $self = shift;

    return time();
}

sub getServerDateTime {
    my $self = shift;

    my @v = gmtime();

    return sprintf('%d-%02d-%02d %02d:%02d:%02d', $v[5]+1900,$v[4]+1,$v[3],$v[2],$v[1],$v[0]);
}

=item C<waitForNextTrade($system)>

Sleeps for 20 seconds. $system is ignored.

This method is called by Trader.pl.

=cut
sub waitForNextTrade {
    my ($self, $system) = @_;
    
    sleep(20);
}

1;

=back

=head1 LICENSE

This is released under the MIT license. See L<http://www.opensource.org/licenses/mit-license.php>.

=head1 AUTHOR

Joao Costa - L<http://zonalivre.org/>

=head1 SEE ALSO

L<Server.exe>

=cut