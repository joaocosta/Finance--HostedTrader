package Finance::HostedTrader::Report;
=head1 NAME

    Finance::HostedTrader::Report - Report object

=head1 SYNOPSIS

    use Finance::HostedTrader::Report;
    my $report = Finance::HostedTrader::Report->new(
                    account => $account,
                    system  => $system,
                );
    print $report->openPositions;
    print $report->systemEntryExit;

=head1 DESCRIPTION


=head2 METHODS

=over 12

=cut

use strict;
use warnings;
use Moose;
use Moose::Util::TypeConstraints;

use Params::Validate qw(:all);

=item C<account>


=cut
has account => (
    is     => 'ro',
    isa    => 'Finance::HostedTrader::Account',
    required=>1,
);

=item C<system>

=cut
has system => (
    is      => 'ro',
    isa     => 'Finance::HostedTrader::Systems',
    required=> 1,
);

=item C<format>

=cut
enum 'enumFormat' => qw(text html);
has format => (
    is      => 'rw',
    isa     => 'enumFormat',
    required=> 1,
    default => 'text'
);


=item C<openPositions>


=cut

sub openPositions {
    my $self = shift;
    my $account = $self->account;
    my $system = $self->system;
    my $positions = $account->getPositions();

    my $t = $self->_table_factory( format=> $self->format, headingText => 'Open Positions', cols => ['Symbol', 'Open Date','Size','Entry','Current','PL','%'] );

    foreach my $symbol (keys %$positions) {
    my $position = $positions->{$symbol};

    foreach my $trade (@{ $position->trades }) {
        my $stopLoss = $system->getExitValue($trade->symbol, $trade->direction);
        my $marketPrice = ($trade->direction eq 'short' ? $account->getAsk($trade->symbol) : $account->getBid($trade->symbol));
        my $baseCurrencyPL = $trade->pl;
        my $percentPL = sprintf "%.2f", 100 * $baseCurrencyPL / $account->getNav;

        $t->addRow(
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
    return $t;
}

sub systemEntryExit {
    my $self = shift;
    my $account = $self->account;
    my $system = $self->system;

    my $t = $self->_table_factory( format => $self->format, headingText => $system->name, cols => ['Symbol','Market','Entry','Exit','Direction', 'Worst Case', '%']);
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
                        sprintf('%.2f',100 * $positionRisk / $account->getNav)
            );
        }
    }
    return $t;
}

sub _table_factory {
    my $self = shift;
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
        require HTML::Table;
        $t = HTML::Table->new(-head => $args{cols});
    } else {
        die("unknown format: $args{format}");
    }

    return $t;
}

__PACKAGE__->meta->make_immutable;
1;

=back


=head1 LICENSE

This is released under the MIT license. See L<http://www.opensource.org/licenses/mit-license.php>.

=head1 AUTHOR

Joao Costa - L<http://zonalivre.org/>

=head1 SEE ALSO

L<Finance::HostedTrader::Trade>

=cut