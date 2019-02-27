# --
# Copyright (C) 2017 - 2018 Perl-Services.de, http://www.perl-services.de/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::FilterContent::HideDynamicFields;

use strict;
use warnings;

our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::System::Queue
    Kernel::System::JSON
    Kernel::System::Web::Request
    Kernel::Output::HTML::Layout
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{UserID}      = $Param{UserID};

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $JSONObject   = $Kernel::OM->Get('Kernel::System::JSON');
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get template name
    #my $Templatename = $Param{TemplateFile} || '';
    my $Action = $ParamObject->GetParam( Param => 'Action' );

    return 1 if !$Action;
    return 1 if !$Param{Templates}->{$Action};

    my $TicketID = $ParamObject->GetParam( Param => 'TicketID' );
    my %Ticket;

    if ( $TicketID ) {
        %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketID,
            UserID   => $LayoutObject->{UserID},
        );
    }

    my $Config = $ConfigObject->Get('HideDynamicFields::Filter') || {};

    my %QueueList        = $QueueObject->QueueList( UserID => 1 );
    my %QueueListReverse = reverse %QueueList;

    my @Binds;
    my %Rules;
    my $HideJS = '';

    for my $Name ( sort keys %{ $Config } ) {
        my $BindJS = sprintf q~$('#%s').bind('change', function() {
            DoHideDynamicFields();
        });~, $Name;

        my $TicketKey = $Name;

        for my $Value ( keys %{ $Config->{$Name} || {} } ) {
            my $OrigValue = $Value;

            if ( $Name eq 'Dest' ) {
                $Value = sprintf "%s||%s", $QueueListReverse{$Value}, $Value;
                $TicketKey = 'Queue';
            }

            my @Fields = split /\s*,\s*/, $Config->{$Name}->{$OrigValue};
            $Rules{$Name}->{$Value} = \@Fields;

            if ( $Ticket{$TicketKey} eq $OrigValue ) {
                $HideJS .= sprintf "HideDynamicField('%s'); ", $_ for @Fields;
            }
        }

        push @Binds, $BindJS;
    }

    my $JSON = $JSONObject->Encode( Data => \%Rules );

    my $JS = qq~
        <script type="text/javascript">//<![CDATA[
        var HideDynamicFieldRules = $JSON;

        function ShowDynamicFields() {
            \$('.Row').show();
        }
        
        function HideDynamicFields() {
            \$('.Row').hide();
        }        
		
		HideDynamicFields();        

        function DoHideDynamicFields() {
            HideDynamicFields();
            \$.each( HideDynamicFieldRules, function( Field, Config ) {
                var Current = \$('#' + Field).val();
                var ToHide  = Config[Current];
                \$.each( ToHide, function( Index, Name ) {
                    HideDynamicField( Name );
                });
            });
        }

        function HideDynamicField( FieldName ) {
            \$('.Row_DynamicField_' + FieldName ).val('');
            \$('.Row_DynamicField_' + FieldName ).show();
        }

        Core.App.Ready( function() {
            @Binds
        });

        $HideJS
        //]]></script>
    ~;

    ${ $Param{Data} } =~ s{</body}{$JS</body};

    return 1;
}

1;
