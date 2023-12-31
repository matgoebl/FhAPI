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
    Log3 $name, 5, "Registering FhAPI $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

sub FhAPI_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 5, "Unregistering FhAPI $name for URL $url...";
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

sub FhAPI_writeval($$$$$) {
    my ($name,$dev,$rdg,$val,$cmd) = @_;
    $cmd="set" if $cmd eq "";
    $dev=~s/[^-a-zA-Z0-9_.]//g;
    $rdg=~s/[^-a-zA-Z0-9_.]//g;
    $val=~s&[^-a-zA-Z0-9_.,;:/#'"|() \$%]&&g;
    Log3 $name, 4, "FhAPI $name: $dev $cmd $rdg=$val";
    if ( $rdg eq "state" ) {
        fhem("$cmd $dev $val");
    } elsif ( $cmd eq "trigger" ) {
        fhem("trigger $dev $rdg $val");
    } else {
        $val="." if $val eq "";
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
        my $h = $defs{$name};
        $h->{SNAME} = $FW_wname;  # FhAPI uses the authorization of the underlying fhemweb instance
        my $cmd = "set";

        my $userHeader = AttrVal($name, "userHeader", undef);
        my $user = defined($userHeader) ? $FW_httpheader{$userHeader} || "" : $FW_wname;

        my $response = AttrVal($name, $user."_Response", "OK");
        my $rdevs  = AttrVal($name, $user."_RDevices", "");
        my $rwdevs = AttrVal($name, $user."_RWDevices", "");
        my $defaultrdevs = AttrVal($name, "defaultRDevices", "");
        my $defaultrwdevs = AttrVal($name, "defaultRWDevices", "");

        my ($first,$body) = split("&",$request,2);

        Log3 $name, 5, "FhAPI $name called: user:$user r:$rdevs rw:$rwdevs resp:$response dev:$dev rdg:$rdg uri:$URI body:".($body?$body:"");

        DoTrigger($name, "$user");

        return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
            "ERROR No endpoint for $link" )
          unless ($name);

        return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
            "ERROR No device $dev" )
          unless ($dev ne "");

        if ( !defined($body) && defined($FW_webArgs{set}) ) {
            $cmd = "set";
            $body = $FW_webArgs{set};
            Log3 $name, 5, "FhAPI $name: use set=$body from url as body";
        }

        if ( !defined($body) && defined($FW_webArgs{trigger}) ) {
            $cmd = "trigger";
            $body = $FW_webArgs{trigger};
            Log3 $name, 5, "FhAPI $name: use trigger=$body from url as body";
        }

        if ( !defined($body) ) {

            return FhAPI_ReturnError($name, "text/plain; charset=utf-8",
                "ERROR User $user is not autorized to read $dev" )
              unless (!defined($userHeader) && Authorized($h, "cmd", "get") == 1 && Authorized($h, "devicename", $dev) == 1 ) ||
                     ( defined($userHeader) && ( FhAPI_isAuth($dev,$rdevs) || FhAPI_isAuth($dev,$rwdevs) ||
                                                 FhAPI_isAuth($dev,$defaultrdevs) || FhAPI_isAuth($dev,$defaultrwdevs) ) );

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
              unless ( !defined($userHeader) && Authorized($h, "cmd", $cmd) == 1 && Authorized($h, "devicename", $dev) == 1 ) ||
                     ( defined($userHeader) && ( FhAPI_isAuth($dev,$rwdevs) || FhAPI_isAuth($dev,$defaultrwdevs) ) );

            if ( $rdg ne "" ) {
                Log3 $name, 3, "FhAPI $name: $user $cmd $dev:$rdg=$body";
                FhAPI_writeval($name,$dev,$rdg,$body,$cmd);
                return ( "text/plain; charset=utf-8", $response );

            } else {

                my $json;
                eval {
                    $json = decode_json($body);
                    1;
                } or do {
                    return FhAPI_ReturnError($name, "text/plain; charset=utf-8", "ERROR Invalid JSON data received" );
                };
                my $hash = $defs{$dev};
                return FhAPI_ReturnError($name, "text/plain; charset=utf-8", "ERROR Unknown device $dev" ) if ! defined($hash);
                if( ref($json) eq "HASH" ) {
                    Log3 $name, 3, "FhAPI $name: $user $cmd $dev=".encode_json($json);
                    readingsBeginUpdate($hash);
                    while ( my ( $key, $value ) = each %{ $json } ) {
                        if( ref($value) eq "HASH" || ref($value) eq "ARRAY" ) {
                            $value = encode_json($value); # TODO: extract full structure
                        }
                        readingsBulkUpdate($hash, $key, $value);
                    }
                    readingsEndUpdate($hash, 1);
                    return ( "text/plain; charset=utf-8", $response );
                }
            }
        }

    }

    return FhAPI_ReturnError(undef, "text/plain; charset=utf-8", "ERROR Invalid URL $request" );
}

1;


=pod
=item helper
=item summary    provides a REST-like web API with user specific device authorization
=item summary_DE bietet ein REST-ähnliches Web-API mit benutzerspezifischen Geräterechten
=begin html

<a name="FhAPI"></a>
<h3>FhAPI</h3> 
<ul>
  <a name="FhAPIabout"></a>
  <b>About</b>
  <ul>
    <p>
    FhAPI provides a REST-like web API with user specific device authorization.
    </p>
    <p>
      <b>When you need this module:</b><br>
        <ul>
          <li>You have different embedded devices acting as sensors/actors out there and they
          need to get or set readings via http(s)</li>
          <li>You don't want to distribute a common fhem password that can be used to execute
          arbitrary fhem commands</li>
          <li>You want control and restrict what can be done by a user</li>
          <li>You want a clear and REST-like access to your device using hierarchical urls.</li>
        </ul>
    <p>
      <b>Comparison to standard FHEM web interface:</b><br>
      You don't need this module, if it is sufficient for you to execute
      plain fhem commands via HTTP:
      <ul>
        <li><code>http://yourserver/fhem?cmd=set+Light+on</code></li>
        <li><code>http://yourserver/fhem?XHR=1&cmd=list+Light</code></li>
      </ul>
      Currently fhem can restrict web interface instances to certain commands (e.g. get only),
      but it cannot restrict a web interface to a limited set of devices.
      Devices can be hidden, but this doesn't guarantee security.
    </p>
    <p>
      <b>Limitations of this module:</b><br>
        <ul>
          <li>This module does only <i>authorization</i>, i.e. limit per user access to
          a given list of devices.</li>
          <li>This module does not do <i>authentication</i>, i.e. check a users password.
              You need a frontend webserver or reverse web proxy like <a href="https://nginx.org/">nginx</a> to do this.</li>
          <li>Additional limitations by the underlying web server implementation FHEMWEB:
           <ul>
            <li>PUT and DELETE methods are not supported.</li>
            <li>The content-type request header is ignored.</li>
            <li>Avoid having a "&amp;" within the URL: FHEMWEB uses a "&amp;" to mark the beginning of the POST body.
             Be aware that some implementations automatically add fields, e.g. jQuery might add "&amp;_=1234567" to prevent
             caching!</li>
           </ul>
          </li>
         <li>So this interface is not 100% RESTful.</li>
        </ul>
    </p>
    <p>
      <b>Example use:</b><br>
      <ul>
       <li>Get the state: GET <code>https://yourserver/fhapi/Light/state/</code> gives <code>on</code></li>
       <li>Get all readings: GET <code>https://yourserver/fhapi/Light/</code> gives <code>{"state":"on"}</code></li>
       <li>Set a single reading: POST <code>on</code> to <code>https://yourserver/fhapi/Light/state/</code></li>
       <li>Set a single reading (alternative method for clients that do not support POST): GET <code>https://yourserver/fhapi/Light/state/?set=on</code></li>
       <li>Trigger an event: GET <code>https://yourserver/fhapi/Light/state/?trigger=timer</code> causes a "trigger Light timer"</li>
       <li>Set multiple readings at once: POST <code>{"state":"on","color":"blue"}</code> to <code>https://yourserver/fhapi/Light/</code></li>
       <li>Get all readings: GET <code>https://yourserver/fhapi/Light/</code> gives <code>{"state":"on","color":"blue"}</code></li>
       <li>Get a single reading: GET <code>https://yourserver/fhapi/Light/color/</code> gives <code>blue</code></li>
      </ul>
    </p>
  </ul>
  <br>

  <a name="FhAPIdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FhAPI &lt;basepath&gt;</code><br>
    <p>
      This module provides a REST-like web API with user specific device authorization at
      &lt;fhembaseurl&gt;/&lt;basepath&gt;
    </p>
    <p>
      Example:
      <code>define webapi FhAPI api</code><br>
      This exposes your API instance webapi at <code>http://yourserver/fhem/api/</code>
    </p>
  </ul>

  <a name="FhAPIattr"></a>
  <b>Attributes</b>
  <ul>
    <li>userHeader<br>
      optional: Inherit (and trust!) the authenticated username from your frontend webserver in the given HTTP header.<br>
      default: use allowedCommands (get/set/trigger) and allowedDevices from the allowed device valid for the corresponding web instance.
    </li> 
    <li>&lt;username&gt;_RDevices<br>
      optional: Comma-separated List of devices that the user &lt;username&gt; is allowed to read,
      i.e. perform GET on its readings. May contain regular expressions that match on several device names.<br>
      example: <code>attr webapi sensor1_RDevices MainDoor,.*Light</code><br>
      (only used if userHeader is set)
    </li>
    <li>&lt;username&gt;_RWDevices<br>
      optional: Comma-separated List of devices that the user &lt;username&gt; is allowed to read and write,
      i.e. perform GET and POST on its readings. May contain regular expressions.<br>
      example: <code>attr webapi sensor1_RWDevices Sensor1,OutsideLight</code><br>
      (only used if userHeader is set)
    </li>
    <li>&lt;username&gt;_Response<br>
      optional:Answer to POST requests from this device. The default response is "OK".<br>
      example: <code>attr webapi sensor1_Response !cfg.power_timeout=10000</code><br>
      (only used if userHeader is set)
    </li>
    <li>defaultRDevices<br>
      optional: Comma-separated List of devices that all users are allowed to read.<br>
      example: <code>attr webapi defaultRDevices OutsideTemperature</code><br>
      (only used if userHeader is set)
    </li>
    <li>defaultRWDevices<br>
      optional: Comma-separated List of devices that all users are allowed to read and write.<br>
      notice: if you just want a RESTful interface without user limitations, you might only set
      defaultRDevices and defaultRWDevices.<br>
      (only used if userHeader is set)
    </li>
  </ul>
  <br>

  <a name="FhAPIexamples"></a>
  <b>Installation, configuration and usage examples</b> 
  <ul>
   <li>Installation:
   <br>In order to install FhAPI just copy the perl module into your FHEM modules directory (distribution specific), e.g.:
    <pre>
      cp 98_FhAPI.pm /opt/fhem/FHEM/
    </pre>
   </li>
   <li>FHEM configuration:
    <pre>
      define webapi FhAPI api
      attr webapi userHeader X-Remote-User
      attr webapi defaultRDevices OutsideTemperature
      attr webapi sensor1_RDevices MainDoor,.*Light
      attr webapi sensor1_RWDevices Sensor1
      defmod WEBapi FHEMWEB 8084 global
      attr WEBapi csrfToken none
      attr WEBapi webname apifhem
      defmod allowed_WEBapi allowed
      attr allowed_WEBapi allowedCommands ,
      attr allowed_WEBapi allowedDevices ,
      attr allowed_WEBapi basicAuth dXNlcjpwYXNzd29yZA==
      attr allowed_WEBapi validFor WEBapi
    </pre>
   </li>
   <li>Nginx frontend configuration:
    <pre>
      location /fhapi {
          auth_basic_user_file /etc/nginx/conf/htpasswd_fhapi;
          # generate: echo -n 'user:password'|base64 
          proxy_set_header Authorization "Basic dXNlcjpwYXNzd29yZA==";
          proxy_pass 'http://127.0.0.1:8084/apifhem/api';
          proxy_set_header X-Remote-User $remote_user;
      }
    </pre>
   </li>
   <li>Accessing the Web API:
    <pre>
      # Secure access using cURL:
      curl -s https://switch123:secRet@192.168.1.1/fhapi/SomeLight/
      curl -s -d on https://switch123:secRet@192.168.1.1/fhapi/SomeLight/state
      curl -s -H 'Content-Type: application/json' -d '{"state":"off","powersave":"on"}' https://switch123:secRet@192.168.1.1/fhapi/SomeLight/state
      # Some embedded OpenWRT linux system with no space for a full-blown curl:
      wget -q -O - "http://switch123:secRet@192.168.1.1/fhapi/SomeLight/state?set=on"
    </pre>
   </li>
  </ul>
</ul>

=end html
=cut
