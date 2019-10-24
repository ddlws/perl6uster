perl6uster
====================================

## Description

Perl6uster is an easily extendable [gobuster](https://github.com/OJ/gobuster) clone with a few new tricks. It offers wordlist filtering/mutating and more authentication schemes. If you have a parallelizable problem that involves a wordlist, the plugin interface is very easy to use. Syntax and output copy gobuster's as closely as possible.

### Added features
* Wordlist filtering and mutating with perl6 regular expressions
    * filters and mutators can be passed on the command line or added on the fly
    * mutators can use perl6's s/// and tr/// operators
* More authentication options thanks to [libcurl](https://curl.haxx.se/libcurl/c/CURLOPT_HTTPAUTH.html) and [LibCurl::Easy](https://github.com/CurtTilmes/perl6-libcurl)
    * Basic, Bearer, Digest, Negotiate(NYI), NTLM
* Extremely easy plugin development.
    * auto-configures libcurl
    * a simple plugin only requires one method implementation

## TOC
* [Why](#why)
* [Using it](#using-it)
* [Using filters and mutators](#using-filters--mutators)
* [Plugins](#plugins)
    * [Using plugins](#using-plugins)
    * [Interface](#interface)
        * Options
            * [Reading global options](#accessing-cmdline-options)
            * [Defining new options](#defining-new-options)
        * [Using libcurl](#using-libcurl)
        * [method PlugInit()](#method-pluginit)
        * [method ThreadInit()](#method-threadinit)
        * [method Process()](#method-processstr-word-opt)
            * [Result class](#results)
        * [method ResultToString()](#method-resulttostringresult-r)
    * [Complete example](#a-complete-example)
* [Example output](#example-output)

### Why?

I like gobuster. OJ has written some popular things, so I though I might learn something by porting it. I also like perl6 and wanted to write more of it without worrying over requirements/design.

Regarding speed, sometimes there is a big difference, and sometimes there's no difference; it depends on the network. For reference, perl6uster tops out at around 2000 requests per second from host->vm on my ancient i5. If you need to hammer something with raft-large on a fast link, use gobuster. Use perl6uster if you want to write a quick plugin or need the filters/authentication. I use them both regularly.

## Using it

perl6uster's options are very similar gobuster's. The biggest change is that options with a value must include an equal sign.
```
gobuster -u 'https://example.com/' -t 7 -w '/path2wordlists/raft-small-directories.txt'

perl6uster -u='https://example.com/' -t=7 -w='/path2wordlists/raft-small-directories.txt'
```
DNS mode takes `-R` and `-C` instead of '-r' and '-c'. There are some new ones, and there are no '--longoptions'. Regardless, they're close enough that most commandlines are transferable if you twiddle the equal signs.

Perl6uster options:
```
Global options:
  -h                      Use perl6uster <mode> -h for plugin-specific help
  -delay=<int>            Each thread pauses this long between requests
                            '-delay=5' and '-delay=5000ms' both wait 5 seconds
  -filt='/a regex/'       Filter words that match the regex. Can be passed multiple times.
  -mut='s/a/bbb/'         Mutate words with 's///' or 'tr///'. Can be passed multiple times.
  -sndorig                Send original word along with its mutations (default does not)
  -o=<outfile path>       Output file to write results to (defaults to stdout)
  -pause                  Start perl6uster paused. Use when you want to add filters
                            without fighting shell quoting.
  -q                      Don't print the banner and other noise
  -t=<int>                Number of concurrent threads (default 10)
  -v                      Verbose output (errors)
  -w=<wordlist path>      Path to the wordlist. Leave it blank to pipe over stdin
  -z                      Don't display progress
  -fw                     Force continued operation when wildcard found (dir & dns)
  HTTP options:
    -auth=<basic|bearer|digest|ntlm>
                            Authentication mode to use. case insensitive
    -a=<UA string>          Set the User-Agent string (default "perl6uster/0.1.0")
    -c=<string>             Cookies to use for the requests
    -r                      Follow redirects
    -k                      Skip SSL certificate verification
    -n                      Don't print status codes
    -p=<proxy>              Proxy to use for requests [http(s)://host:port]
    -to=<duration>          HTTP Timeout (default 10s)
    -u=<url>                The target URL
    -H=<string:string>      Specify HTTP headers, -H 'key1: val1' -H 'key2: val2'
    -P=<password>           Password for authentication
    -U=<username>           Username for authentication
    -T=<tokenstring>        Bearer access token for Bearer authentication
dir mode options:
  -b=<string>              Negative status codes (will override statuscodes if set)
  -e                       Expanded mode, print full URLs
  -f                       Append '/' to each request
  -l                       Include the length of the body in the output
  -s=<string>              Positive status codes
                             (default "200,204,301,302,307,401,403")
  -x=<string>              File extension(s) to search for

dns mode options:
  -d=<string>               The target domain
  -h                        help for dns
  -R=<string>               Use custom DNS server (ip address)
  -C                        Show CNAME records (cannot be used with '-i' option)
  -i                        Show IP addresses

vhost mode options: Only the global/http options apply
```

### Using filters & mutators

#### Filters

Wordlist filters are [perl6 regular expressions](http://docs.perl6.org/language/regexes). These are entered exactly as they would appear in perl6 code. **They are tested in a child process and then passed to EVAL()**, so standard warnings about running code you don't understand apply here.

Words that match any provided filters are skipped. You can pass any number of filters on the commandline using `-filt='/someregex/'`. If you want to try perl6 code injection, this is an [easy one](http://docs.perl6.org/language/operators):
> my $result = run $*EXECUTABLE.absolute(), '-e', "'TESTSTRING123' ~~ $rgx;", :out, :err;

For example, if you know a server returns 403 for any filenames starting with `.ht` or ending with `.phps`, you could prevent those requests with this:
`-filt='/ ^\.ht /' -filt='/ \.phps$ /'`. Note that you don't have to match the entire word.

If the shell is causing problems, you can pause perl6uster before it makes any requests by passing `-pause` on the cmdline. You can then add your regex via the menu shown below.

#### Mutators
Mutators work similarly, but are restricted to the perl6 `s///` and `tr///` operators. Pass them on the command line with `-mut=`.
> -mut='s/this/that/' -mut='tr/a/A/'

If no mutators have an effect on a given word, that word is always sent in a request. New words generated by mutators are always sent in a request.

By default, the original word is *NOT* sent in a request if any mutators result in new words. You can change this by passing `-sndorig` on the cmdline. Examples to demonstrate:

Given a wordlist containing 'a','b','c':
* `-mut='tr/a/A/' -mut='s/b/0wn3d/'` sends requests for /A, /0wn3d, and /c
* `-mut='tr/a/A/' -mut='s/b/0wn3d/' -sndorig` sends requests for /A, /a, /0wn3d, /b, and /c

#### Adding filters/mutators at runtime

###### This will not work when piping the wordlist over stdin.

If requests containing a certain pattern are polluting results or *may draw unwanted attention*, you can pause perl6uster by pressing **p** (active requests will complete). This presents a menu:

```
Options:

Add filter
Add mutator
List filters
List mutators
Resume busting
```

### Wordlists via STDIN

Pipe in a wordlist by leaving out the `-w` option. Perl6uster's keybinds won't work when doing this.
```
hashcat -a 3 --stdout '?l' | perl6uster dir -u=https://mysite.com
```

## Plugins

### Using plugins

It's easy; pass the path to your source file as the first parameter.
> perl6uster '/path/to/theplugin.pm6' [-options]

### Writing plugins

This will explain the interface and show some examples taken from the core plugins.

### Interface
Plugins consist of a single class. That class inherits the plugin interface through the `perl6uster-plugin` role.

**Critical:** The last thing in your source file has to be the class definition. Textual inclusion of perl6 source code isn't as easy as you might think. If you have anything after the class definition, perl6uster will die and tell you to 'rtfm'. Just put everything inside the class, and you won't have ~~any problems~~ this problem.
```perl6
#Defines the plugin interface.
role perl6uster-plugin {
    has Buster $!buster;
    method Process(Str $word, :%opt) {...}
    method ResultToString(Result $r) { return $r.Entity } #optional
    method PlugInit() { return } #optional
    method ThreadInit() { return } #optional
    method PrintConfig() { return } #optional
    method Help() { return } #optional
}
```
While only `Process()` is required, You'll usually need `PlugInit()` and `ThreadInit()`, too.

### Boilerplate
There isn't much:
```perl6
use perl6uster::buster; # always required
use perl6uster::curl; # not required, but recommended if you're making requests

class plug-example does perl6uster-plugin {
    ...
}
```

#### Accessing cmdline options

 The `perl6uster-plugin` role puts the main `buster` object in `$!buster`. This gives you access to all of the options passed on the commandline. Read them like this: `$!buster.threads`.
```
    #general options
    delay   mode    noProgress    noStatus    outfile    quiet    threads    verbose
    wildcardForced    wordlist

    #http options
    auth    cookies     followRedirect    httpheaders    insecureSSL    password
    proxy    timeout    token    url    userAgent    username
```

#### Defining new options

You define new options in the plugin's constructor. It should be clear given an example. Here is the DNS plugin's constructor in it's entirety:
```perl6
submethod TWEAK(:d(:$!domain),                      :R(:$!resolver),
                Bool :c(:$!showCNAME)=False,        Bool :i(:$!showIP)=False )
    { $!client .= new($!resolver) }
```
That sets up the DNS flags `-d=<domain>`, `-R=<DNS server>`, `-c`, and `-i` and assigns their passed-in values to the `$!domain`, `$!resolver`, `$!showCNAME`, and `$!showIP` class attributes, respectively.

#### Using libcurl
perl6uster generates libcurl options for you using the http options passed on the command line. It'll even set headers if you `use perl6uster::curl;`.

It's just a small wrapper for [Libcurl::Easy](https://github.com/CurtTilmes/perl6-libcurl), but it makes working with headers much easier. `$!buster.curlopts` returns a hash holding your options. To instantiate a client:
> my $client = curl.new(|$!buster.curlopts);

You can modify `curlopts` like this `$!buster.curlopts('option' => value);`. Find the list of available options [here.](https://github.com/CurtTilmes/perl6-libcurl#options)

[Libcurl::Easy](https://github.com/CurtTilmes/perl6-libcurl) is great, and you have full access to it through `$client.easy`. Read [curldoc.md](https://github.com/ddlws/perl6uster/blob/master/curldoc.md) to see the convenience methods in `perl6uster::curl`.

### method PlugInit()
This is where you do initialization/configuration before worker threads start. This example is an excerpt from the vhost plugin. It's updating a libcurl option (use HEAD requests) that'll affect the worker threads later.
```perl6
#make a decision
$use-etag = ?$base-etag && ?$nonex-etag ?? True !! False;
$!buster.curlopts('nobody'=> 1) if $use-etag;
```

### method ThreadInit()
This method is for initializing resources that can't be shared across threads. If you aren't using such a resource, you don't need to define this method. It gets called once for each worker thread (the '-t' option). **If you implement it, it must return a `Hash`.** perl6uster doesn't care what you put in the hash or what keys you use. The dir and vhost plugins both use the code below. Since they're using libcurl, they have to create a new client for each thread.

```perl6
method ThreadInit() {
    #instantiate libcurl
    return %(client => curl.new(|$!buster.curlopts) );
}
```
### method Process(Str $word, :%opt)
This method takes a word from the wordlist and does something with it. For dir and vhost, they get a `perl6uster::curl` instance passed in `%opt<client>`, since that's what they return in `ThreadInit()`. Here is part of the vhost plugin to show it in use:
```perl6
method Process(Str $word, :%opt) {
        my $client := %opt<client>;
        #update our Host header & send request
        my $host = $word~'.'~$dom;
        $client.set-header('Host'=>$host);
        $client.perform;
        ...
```

##### Results
`Process()` needs to return a `Result` object. It's definition is shown below. Set `$!Hit` to True for positive results. You can use the other attributes however you want, though `Extra` is the only attribute without a type constraint. The others have default values, so you don't have to assign any values you don't need. You'll get your `Result` passed back to you in `ResultToString()`.
```perl6
class Result {
    has Str $.Entity='';
    has int $.Status=0;
    has $.Extra;
    has int $.Size=0;
    has Bool $.Hit=False;
}
```
Here is the rest of vhost's `Process` for any visual learners:
```perl6
my $Hit=False;
if $use-etag {
    my $t = $client.get-header('etag');
    if not ?$t {$Hit = True} #hit if no etag
    else {
        $Hit = True if $t ne $base-etag && $t ne $nonex-etag; #hit if different
    }
}
else {
    my $t = $client.buf;
    $Hit = True if $t != $base-buf && $t != $nonex-buf; #hit if different body
}
return Result.new(Entity=>$host, :$Hit);
```
### method ResultToString(Result $r)
Take a Result object and return the string you want printed. **This only gets called for positive results**, unless you've turned on the verbose option. The default implementation returns `$r.Entity`, which will be good enough in most cases. The DNS implementation:

```perl6
method ResultToString(Result $r) {
        my Str $retstr='';
        if ?$r.Hit { $retstr ~= "Found: " }
        else { $retstr ~= "Missed: " }

        #build the string
        $retstr ~= $r.Entity~' ';
        if $!showIP || $!showCNAME { $retstr ~= $r.Extra }
        return $retstr;
}
```

### A complete example

Here is the vhost plugin, since it's the shortest:
```perl6
use perl6uster::buster;
use perl6uster::curl;
use perl6uster::common;

class plug-vhost does perl6uster-plugin {

    my Bool $use-etag;
    my Str $dom;
    my Buf $base-buf;
    my $base-etag;
    my Buf $nonex-buf;
    my $nonex-etag;
    my $labelrx = ::('$domlabel');

    method PlugInit() {
        #pull the domain from the url
        $!buster.url ~~ /https?\:\/\/(<-[ / ]>+)/;
        dwd("Fix the URL: {$!buster.url}",$?FILE, $?LINE) unless ?$/[0];
        $dom = $/[0].Str;
        $!buster.curlopts('nobody'=> 0);

        #test client & grab baselines for comparison
        my $client = curl.new(|$!buster.curlopts);
        $client.perform();
        #domain in the url
        $base-etag = $client.get-header('etag');
        $base-buf = $client.buf;

        #nonexistant subdomain
        $client.set-header('Host'=>wildstr~'.'~$dom);
        $client.perform();
        $nonex-etag = $client.get-header('etag');
        $nonex-buf = $client.buf;

        #`(use them if the base domain and the nonexistent domain return them. We can
        make HEAD requests if we don't need the body)
        $use-etag = ?$base-etag && ?$nonex-etag ?? True !! False;
        $!buster.curlopts('nobody'=> 1) if $use-etag;
    }
    method ThreadInit() {
        #instantiate libcurl
        return %(client => curl.new(|$!buster.curlopts) );
    }
    method Process(Str $word, :%opt) {
        #skip word if it's not a valid label
        return Nil unless $word ~~ $labelrx;
        my $client := %opt<client>;
        #update our Host header & send request
        my $host = $word~'.'~$dom;
        $client.set-header('Host'=>$host);
        $client.perform;

        my $Hit=False;
        if $use-etag {
            my $t = $client.get-header('etag');
            if not ?$t {$Hit = True} #hit if no etag
            else {
                $Hit = True if $t ne $base-etag && $t ne $nonex-etag; #hit if different
            }
        }
        else {
            my $t = $client.buf;
            $Hit = True if $t != $base-buf && $t != $nonex-buf; #hit if different body
        }
        return Result.new(Entity=>$host, :$Hit);
    }
}
```

## Example output
Dir with length
```
perl6uster dir -u='http://192.168.0.10' -w=quickhits.txt -t=7 -l

=====================================================
perl6uster v0.1.0          Dave Lewis
=====================================================
[+] Url/Domain   : http://192.168.0.10/
[+] Status codes : 200,204,301,302,307,401,403
[+] User Agent   : perl6uster/0.1.0
[+] Timeout      : 10
[+] Show length  : true
[+] Mode         : dir
[+] Threads      : 7
[+] Wordlist     : quickhits.txt
=====================================================
Starting perl6uster: 2019-10-10 15:40:58
=====================================================
Found: //.htaccess (Status: 200) [Size: 0]
Found: //1.txt (Status: 200) [Size: 0]
Found: //admin/ (Status: 403) [Size: 169]
Found: //dev/ (Status: 403) [Size: 169]
=====================================================
Finished: 2019-10-10 15:41:00
=====================================================
```
Quiet with leading slashes trimmed
```
perl6uster dir -u='http://192.168.0.10' -w=quickhits.txt -t=7 -l -mut='s/^\///' -q

Found: /.htaccess (Status: 200) [Size: 0]
Found: /1.txt (Status: 200) [Size: 0]
Found: /admin/ (Status: 403) [Size: 169]
Found: /dev/ (Status: 403) [Size: 169]
```
DNS
```
perl6uster dns -d='perl6.org' -t=5 -w=dnswl.txt -R='8.8.8.8'

=====================================================
perl6uster v0.1.0          Dave Lewis
=====================================================
[+] Domain       : perl6.org
[+] Resolver     : 8.8.8.8
[+] Show CNAME   : False
[+] Show IPs     : False
[+] Timeout      : 10
[+] Mode         : dns
[+] Threads      : 5
[+] Wordlist     : dnswl.txt
=====================================================
Starting perl6uster: 2019-10-10 15:57:07
=====================================================
Found: docs.perl6.org
Found: modules.perl6.org
Found: design.perl6.org
Found: doc.perl6.org
=====================================================
Finished: 2019-10-10 15:57:08
=====================================================
```
DNS with -q -i
```
perl6uster dns -d='perl6.org' -t=5 -w=dnswl.txt -R='8.8.8.8' -i -q

Found: docs.perl6.org 2606:4700:0020:0000:0000:0000:681a:06c9, 2606:4700:0020:0000:0000:0000:681a:07c9, 104.26.6.201, 104.26.7.201
Found: modules.perl6.org 2606:4700:0020:0000:0000:0000:681a:07c9, 2606:4700:0020:0000:0000:0000:681a:06c9, 104.26.7.201, 104.26.6.201
Found: doc.perl6.org 2606:4700:0020:0000:0000:0000:681a:07c9, 2606:4700:0020:0000:0000:0000:681a:06c9, 104.26.6.201, 104.26.7.201
Found: design.perl6.org 2606:4700:0020:0000:0000:0000:681a:07c9, 2606:4700:0020:0000:0000:0000:681a:06c9, 104.26.6.201, 104.26.7.201
```

vhost
```
perl6uster vhost -u='https://perl6.org' -w=dnswl.txt

=====================================================
perl6uster v0.1.0          Dave Lewis
=====================================================
[+] Mode         : vhost
[+] Threads      : 4
[+] Wordlist     : dnswl.txt
=====================================================
Starting perl6uster: 2019-10-10 16:34:38
=====================================================
docs.perl6.org
doc.perl6.org
design.perl6.org
modules.perl6.org
=====================================================
Finished: 2019-10-10 16:34:39
=====================================================
```
## License

See the LICENSE file.
