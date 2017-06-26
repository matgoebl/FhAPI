################################################################
# $Id: 98_FhAPI.pm $
#
#  Copyright notice
#
#  (c) 2017 Copyright: Matthias Goebl
#  e-mail: matthias dot goebl at goebl dot net
#
#  Description:
#  This is an FHEM-Module that provides a REST-style web API
#  with user specific device authorization
#
#  Origin:
#  https://github.com/matgoebl/FhAPI
#
#  License:
#  GNU General Public License v2.0
#
################################################################

package main;
use strict;
use warnings;
use JSON;

use vars qw(%FW_webArgs); # all arguments specified in the GET

sub FhAPI_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'FhAPI_Define';
    $hash->{UndefFn}    = 'FhAPI_Undef';

    $hash->{AttrList} =
          "formal:yes,no "
        . "userHeader "
        . ".*_Response "
        . ".*_RDevices "
        . ".*_RWDevices "
        . "defaultRDevices "
        . "defaultRWDevices "
        . $readingFnAttributes;
}

sub FhAPI_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering FhAPI $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

sub FhAPI_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering FhAPI $name for URL $url...";
    delete $data{FWEXT}{$url};
}

sub FhAPI_Define($$) {
    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> FhAPI <infix>"
      if ( int(@a) != 3 );
    my $name  = $a[0];
    my $infix = $a[2];

    $hash->{name}  = $a[0];
    $hash->{url}   = $a[2];
    $hash->{fhem}{infix} = $infix;

    FhAPI_addExtension( $name, "FhAPI_CGI", $infix );

    return undef;
}

sub FhAPI_Undef($$) {
    my ($hash, $arg) = @_; 
    my $name = $hash->{NAME};

    if ( defined( $hash->{fhem}{infix} ) ) {
        FhAPI_removeExtension( $hash->{fhem}{infix} );
    }

    return undef;
}

sub FhAPI_setval($$$$) {
    my ($name,$dev,$rdg,$val) = @_;
    $dev=~s/[^-a-zA-Z0-9_.]//g;
    $rdg=~s/[^-a-zA-Z0-9_.]//g;
    $val=~s&[^-a-zA-Z0-9_.,;:/#|() \$]&&g;
    Log3 $name, 4, "FhAPI $name: set $rdg=$val";
    if ( $rdg eq "state" ) {
        fhem("set $dev $val");
    } else {
        fhem("setreading $dev $rdg $val");
    }
}

sub FhAPI_isAuth($$) {
    my ($dev,$adevs) = @_;
    foreach my $a ( split( ",", $adevs ) ) {
        return 1 if $a eq $dev;  # just to be sure and if the device name contains special chars (shouldn't)
        return 1 if $a eq "*";   # shortcut for ".*"
        return 1 if $dev=~/^$a$/;
    }
    return 0;
}

sub FhAPI_ReturnError($$$) {
    my ($name,$encoding,$message) = @_;
    Log3 $name, 2, "FhAPI $name ERROR: $message";
    return ($encoding,$message);
}

sub FhAPI_CGI() {
    my ($request) = @_;
    
    if ( $request =~ m,^(\/[^?/&]+)(\/([^?/&]*))?(\/([^?/&]*)\/?)?[^?/&]*(\?(.*))?.*$, ) {
        my $link = $1;
        my $dev  = $3?$3:"";
        my $rdg  = $5?$5:"";
        my $URI  = $7?$7:"";

        my $name = $data{FWEXT}{$link}{deviceName} if ( $data{FWEXT}{$link} );
        my $userHeader = AttrVal($name, "userHeader", "X-User");
	my $user = $FW_httpheader{$userHeader} || "";
	my $response = AttrVal($name, $user."_Response", "OK");
	my $rdevs  = AttrVal($name, $user."_RDevices", "");
	my $rwdevs = AttrVal($name, $user."_RWDevices", "");
	my $defaultrdevs = AttrVal($name, "defaultRDevices", "");
	my $defaultrwdevs = AttrVal($name, "defaultRWDevices", "");
        my ($first,$body) = split("&",$request,2);

        Log3 $name, 3, "FhAPI $name called: user:$user r:$rdevs rw:$rwdevs resp:$response dev:$dev rdg:$rdg uri:$URI body:".($body?$body:"");

        DoTrigger($name, "$user");

        return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
            "ERROR No endpoint for $link" )
          unless ($name);

        return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
            "ERROR No device $dev" )
          unless ($dev ne "");

        if ( !defined($body) && defined($FW_webArgs{set}) ) {
            Log3 $name, 4, "FhAPI $name: use set=$FW_webArgs{set} from url as body";
            $body = $FW_webArgs{set};
        }

        if ( !defined($body) ) {

            return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
                "ERROR User $user is not autorized to read $dev" )
              unless FhAPI_isAuth($dev,$rdevs) || FhAPI_isAuth($dev,$rwdevs) || FhAPI_isAuth($dev,$defaultrdevs) || FhAPI_isAuth($dev,$defaultrwdevs);

            if ( $rdg ne "" ) {
                my $val = $rdg eq "" ? Value($dev) : ReadingsVal($dev,$rdg,"");
                Log3 $name, 3, "FhAPI $name: $user get $dev:$rdg=$val";
                return ( "text/plain; charset=utf-8", $val );

            } else {
                my $h = $defs{$dev};
                #return ( "application/json", "{}" ) if(!$h);
                my %rdgs;
                if($h) {
                  while ( my ($key, $value) = each %{$h->{READINGS}} ) {
                    #print "key: $key, value: $value\n";
                    $rdgs{$key}=$value->{VAL};
                  }
                }
                my $json = encode_json(\%rdgs);
                Log3 $name, 3, "FhAPI $name: $user get $dev=$json";
                return ( "application/json; charset=utf-8", $json );
            }

        } else {

            return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
                "ERROR User $user is not autorized to write $dev" )
              unless FhAPI_isAuth($dev,$rwdevs) || FhAPI_isAuth($dev,$defaultrwdevs);

            if ( $rdg ne "" ) {
                Log3 $name, 3, "FhAPI $name: $user set $dev:$rdg=$body";
                FhAPI_setval($name,$dev,"state",$body);
                return ( "text/plain; charset=utf-8", $response );

            } else {

                my $json;
                eval {
                    $json = decode_json($body);
                    1;
                } or do {
                    return FhAPI_ReturnError($name, "text/plain; charset=utf-8", "ERROR Invalid JSON data received" );
                };
                if( ref($json) eq "HASH" ) {
                    Log3 $name, 3, "FhAPI $name: $user set $dev=".encode_json($json);
                    while ( my ( $key, $value ) = each %{ $json } ) {
                        FhAPI_setval($name,$dev,$key,$value);
                    }
                    return ( "text/plain; charset=utf-8", $response );
                }
            }
        }

    }

    return FhAPI_ReturnError(undef, "text/plain; charset=utf-8", "ERROR Invalid URL $request" );
}

1;
