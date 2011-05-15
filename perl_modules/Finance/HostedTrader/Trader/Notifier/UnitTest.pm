package Finance::HostedTrader::Trader::Notifier::UnitTest;
=head1 NAME

    Finance::HostedTrader::Notifier - Notifier object

=head1 SYNOPSIS

    use Finance::HostedTrader::Notifier::UnitTest;
    my $obj = Finance::HostedTrader::Notifier::UnitTest->new(
                );

=head1 DESCRIPTION


=cut


use strict;
use warnings;

use Moose;
extends 'Finance::HostedTrader::Trader::Notifier';
use Test::More;
use YAML::Tiny;
use Data::Dumper;

=head2 Properties

=over 12

=item C<expectedTrades>
=cut

has 'expectedTradesFile' => (
    is     => 'ro',
    isa    => 'Str',
    required=>1,
);

=back

=head2 Constructor

=over 12

=item C<BUILD>

Constructor.

=cut

sub BUILD {
sub _load {
    my $file = shift;

    my $yaml = YAML::Tiny->new;
    if (-e $file) {
        $yaml = YAML::Tiny->read( $file ) || die("Cannot read symbols from $file. $!");
    } else {
        return [];
    }

    return $yaml->[0];
}
    my $self = shift;

    $self->{_expectedTrades} = _load($self->expectedTradesFile);
    $self->{_tradeCount} = 0;
    plan tests => scalar(@{$self->{_expectedTrades}});
}

=back


=head2 METHODS


=over 12


=item C<open($trade)>

=cut
sub open {
    my $self = shift;
    my %args=@_;
    
    $self->{_tradeCount}++;

    my $got_trade = {
        symbol      => $args{symbol}, 
        direction   => $args{direction},
        amount      => $args{amount},
        stopLoss    => $args{stopLoss},
        orderID     => $args{orderID},
        rate        => $args{rate},
        value       => $args{currentValue},       
        now         => $args{now},
        nav         => $args{nav},
        balance     => $args{balance},
    };
    
    my $expected_trade = shift @{ $self->{_expectedTrades} };
    
    warn("Was not expecting any more trades !") && exit if (!defined($expected_trade));
 
    is_deeply($got_trade, $expected_trade, "Open trade " . $self->{_tradeCount});
}

=item C<close()>

=cut
sub close {
    my $self = shift;
    my %args=@_;
    
    $self->{_tradeCount}++;

    my $got_trade = {
        symbol      => $args{symbol}, 
        direction   => $args{direction},
        amount      => $args{amount},
        value       => $args{currentValue},       
        now         => $args{now},
        nav         => $args{nav},
        balance     => $args{balance},
    };
    
    my $expected_trade = shift @{ $self->{_expectedTrades} };
    
    warn("Was not expecting any more trades !") && exit if (!defined($expected_trade));
 
    is_deeply($got_trade, $expected_trade, "Open trade " . $self->{_tradeCount});    
}


__PACKAGE__->meta->make_immutable;
1;

=back


=head1 LICENSE

This is released under the MIT license. See L<http://www.opensource.org/licenses/mit-license.php>.

=head1 AUTHOR

Joao Costa - L<http://zonalivre.org/>

=head1 SEE ALSO

L<Finance::HostedTrader::Trader>

=cut