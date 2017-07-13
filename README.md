
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
       <li>GET <code>https://yourserver/fhapi/Light/state/</code> gives <code>on</code></li>
       <li>GET <code>https://yourserver/fhapi/Light/</code> gives <code>{"state":"on"}</code></li>
       <li>POST <code>on</code> to <code>https://yourserver/fhapi/Light/state/</code></li>
       <li>GET <code>https://yourserver/fhapi/Light/state/?set=on</code> is allowed for clients that do not support POST</li>
       <li>POST <code>{"state":"on","color":"blue"}</code> to <code>https://yourserver/fhapi/Light/</code></li>
       <li>GET <code>https://yourserver/fhapi/Light/</code> gives <code>{"state":"on","color":"blue"}</code></li>
       <li>GET <code>https://yourserver/fhapi/Light/color/</code> gives <code>blue</code></li>
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
      default: X-User
    </li> 
    <li>&lt;username&gt;_RDevices<br>
      optional: Comma-separated List of devices that the user &lt;username&gt; is allowed to read,
      i.e. perform GET on its readings. May contain regular expressions that match on several device names.<br>
      example: <code>attr webapi sensor1_RDevices MainDoor,.*Light</code>
    </li>
    <li>&lt;username&gt;_RWDevices<br>
      optional: Comma-separated List of devices that the user &lt;username&gt; is allowed to read and write,
      i.e. perform GET and POST on its readings. May contain regular expressions.<br>
      example: <code>attr webapi sensor1_RWDevices Sensor1,OutsideLight</code>
    </li>
    <li>&lt;username&gt;_Response<br>
      optional:Answer to POST requests from this device. The default response is "OK".<br>
      example: <code>attr webapi sensor1_Response !cfg.power_timeout=10000</code>
    </li>
    <li>defaultRDevices<br>
      optional: Comma-separated List of devices that all users are allowed to read.<br>
      example: <code>attr webapi defaultRDevices OutsideTemperature</code>
    </li>
    <li>defaultRWDevices<br>
      optional: Comma-separated List of devices that all users are allowed to read and write.<br>
      notice: if you just want a RESTful interface without user limitations, you might only set
      defaultRDevices and defaultRWDevices.
    </li>
  </ul>
  <br>

  <a name="FhAPIexamples"></a>
  <b>Examples</b> 
  <ul>
   <li>Device definition:
    <pre>
      define webapi FhAPI api
      attr webapi userHeader X-Remote-User
      attr webapi defaultRDevices OutsideTemperature
      attr webapi sensor1_RDevices MainDoor,.*Light
      attr webapi sensor1_RWDevices Sensor1
    </pre>
   </li>
   <li>Nginx frontend configuration:
    <pre>
      location /fhapi {
          auth_basic_user_file /etc/nginx/conf/htpasswd_fhapi;
          # generate: echo -n 'user:password'|base64 
          proxy_set_header Authorization "Basic dXNlcjpwYXNzd29yZA==";
          proxy_pass 'http://127.0.0.1:8083/fhem/api';
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

