perl6uster
====================================

## Description

Perl6uster is an easily extendable [gobuster](https://github.com/OJ/gobuster) clone with a few new tricks. It offers wordlist filtering/mutating and more authentication schemes. If you have a parallelizable problem that involves a wordlist, the plugin interface is very easy to use. Syntax and output copy gobuster's as closely as possible.

### Added features
* Wordlist filtering and mutating with perl6 regular expressions
    * filters and mutators can be passed on the command line or added on the fly
    * words that match a filter are skipped.
    * mutators can use perl6's s/// and tr/// operators
* More authentication options thanks to [libcurl](https://curl.haxx.se/libcurl/c/CURLOPT_HTTPAUTH.html) and [LibCurl::Easy](https://github.com/CurtTilmes/perl6-libcurl)
    * Basic
    * Bearer
    * Digest
    * Negotiate(NYI)
    * NTLM
* Extremely easy plugin development.
    * autoconfigures libcurl
    * a simple plugin only requires one method implementation

## TOC
* [Using filters and mutators](#using-filters--mutators)
* [Plugins]()
    * [Using plugins]()
    * [Writing plugins]()
        * [Options]()
            * [Reading global options]()
            * [Defining new options]()
        * [Using libcurl]()

### Why?

I like gobuster. OJ has written some popular things, so I though I might learn something by porting it. I also like perl6 and wanted to use some parts of the language I wasn't familiar with.

On a fast local network, the difference in speed is significant. Over the internet, it's not too bad. If you need to hammer things with raft-large, use gobuster everytime. Use perl6uster if you want to write a quick plugin or need the filters/authentication. I use them both.

## Using it

Use it like gobuster; perl6uster's options are a superset of gobuster's. The only difference is options that take a value must include an equal sign.

> gobuster dir -u 'https://example.com/' -t 10 -w '/root/wordlists/raft-small-directories.txt' -l -o root-rsd.txt -f -k
> perl6uster dir -u='https://example.com/' -t=10 -w='/root/wordlists/raft-small-directories.txt' -l -o=root-rsd.txt -f -k

Perl6uster has a few extra options
```
Global options:
  -h                      Use perl6uster <mode> -h for plugin-specific help
  -delay=<int>            Each thread pauses this long between requests
                            '-delay=5' and '-delay=5000ms' both wait 5 seconds
  -filt='/a regex/'       Filter words that match the regex. Can be passed multiple times.
  -mut='s/a/bbb/'         Mutate words with 's///' or 'tr///'. Can be passed multiple times.
  -o=<outfile path>       Output file to write results to (defaults to stdout)
  -pause                  Start perl6uster paused. Use when you want to add filters
                            without fighting shell quoting.
  -q                      Don't print the banner and other noise
  -t=<int>                Number of concurrent threads (default 10)
  -v                      Verbose output (errors)
  -w=<wordlist path>      Path to the wordlist. Leave it blank to pipe over stdin
  -z                      Don't display progress
  HTTP options:
    -auth=<basic|bearer|digest|ntlm>
                            Authentication mode to use. case insensitive
    -a=<UA string>          Set the User-Agent string (default "perl6uster/0.1.0")
    -c=<string>             Cookies to use for the requests
    -fw                     Force continued operation when wildcard found
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
  -c                        Show CNAME records (cannot be used with '-i' option)
  -i                        Show IP addresses
  -to                       DNS resolver timeout (default 1s)
                            Force continued operation when wildcard found

vhost mode options: Only the global options apply
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

The original word is still used in a request when mutators are applied. If a mutator has no effect, no new requests are generated. However, each mutator that produces a new word produces a new request.

#### Adding filters/mutators at runtime

###### This will not work when piping the wordlist over stdin.

If requests containing a certain pattern are polluting results or may draw unwanted attention, you can pause perl6uster by pressing `p` (active requests will complete). This presents a menu:

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

### Interface
Plugins consist of a single class. That class inherits the plugin interface through the `perl6uster-plugin` role.

**Critical:** The last thing in your source file has to be the class definition. Textual inclusion of perl6 source code is not as simple as you might imagine. If you include anything but blank lines or comments after the class definition, perl6uster will tell you to 'rtfm' as it dies. Just put everything inside the class, and you won't have ~~any problems~~ this problem.
```
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
```
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
    delay    idelay    mode    noProgress    noStatus    outfile    quiet    threads    verbose
    wildcardForced    wordlist

    #http options
    auth    cookies     followRedirect    httpheaders    insecureSSL    password
    proxy    timeout    token    url    userAgent    username
```

#### Defining new options

You define new options in the plugin's constructor. It should be clear given an example. Here is the DNS plugin's constructor in it's entirety:
```
submethod TWEAK(:d(:$!domain),                      :R(:$!resolver),
                Bool :c(:$!showCNAME)=False,        Bool :i(:$!showIP)=False )
    { $!client .= new($!resolver) }
```
That sets up the DNS flags `-d=<domain>`, `-R=<DNS server>`, `-c`, and `-i` and assigns their passed-in values to the `$!domain`, `$!resolver`, `$!showCNAME`, and `$!showIP` class attributes, respectively.

#### Using libcurl
perl6uster generates libcurl options for you using the http options passed on the command line. It'll even set headers if you `use perl6uster::curl;`.

It's just a small wrapper for [Libcurl::Easy](https://github.com/CurtTilmes/perl6-libcurl), but it makes working with headers much easier. `$!buster.curlopts` returns a hash holding your options. To instantiate a client:
> my $client = curl.new(|$!buster.curlopts);

[Libcurl::Easy](https://github.com/CurtTilmes/perl6-libcurl) is great, and you have full access to it through `$client.easy`. Read curldoc.md to see the convenience methods in `perl6uster::curl`.

### method PlugInit()
This is where you do initialization/configuration before worker threads start. While the dir,dns, and vhost plugins all define this method, you could easily write them all without it. This is an excerpt from the vhost plugin. It's updating a libcurl option (use HEAD requests) that'll affect the worker threads later.
```
#make a decision
$use-etag = ?$base-etag && ?$nonex-etag ?? True !! False;
$!buster.curlopts('nobody'=> 1) if $use-etag;
```

### method ThreadInit()
This method is for initializing resources that can't be shared across threads. If you aren't using such a resource, you don't need to define this method. It gets called once for each worker thread (the '-t' option). **If you implement it, it must return a `Hash`.** perl6uster doesn't care what you put in the hash or what key(s) you put it in. The DNS plugin doesn't define this method since it doesn't need it. The dir and vhost plugins both use the code below. Since they're using libcurl, they have to create a new client for each thread.

```
method ThreadInit() {
    #instantiate libcurl
    return %(client => curl.new(|$!buster.curlopts) );
}
```
### method Process(Str $word, :%opt)
This method takes a word from the wordlist and does something with it. For dir and vhost, they get a `perl6uster::curl` instance passed in `%opt<client>`, since that's what they return in `ThreadInit()`. Here is part of the vhost plugin to show it in use:
```
method Process(Str $word, :%opt) {
        my $client := %opt<client>;
        #update our Host header & send request
        my $host = $word~'.'~$dom;
        $client.set-header('Host'=>$host);
        $client.perform;
        ...
```

##### Results
`Process()` needs to return a `Result` object. It's definition is shown below. Set `$!Hit` to True for positive results. You can use the other attributes however you want, though `Extra` is the only attribute without a type constraint. The others have default values, so you don't have to use any more than you need. You'll get your `Result` passed back to you in `ResultToString()`.
```
class Result {
    has Str $.Entity='';
    has int $.Status=0;
    has $.Extra;
    has int $.Size=0;
    has Bool $.Hit=False;
}
```
Here is the rest of vhost's `Process` for any visual learners:
```
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
Take a Result object and return the string you want printed. *This only gets called for positive results*, unless you've turned on the verbose option. The default implementation returns `$r.Entity`, which will be good enough in most cases. For the core plugins:

* vhost doesn't define it
* dir's is "long" at 16 lines due to the commandline affecting output
* DNS implementation is here:

```
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

Here is a simplified version of the vhost plugin, since it's the shortest:
```perl6
use perl6uster::buster;
use perl6uster::curl;
use perl6uster::common;

class plug-vhost does perl6uster-plugin {

    my Str $dom; #the domain which we'll parse from the url arg
    my Buf $base-buf;
    my Buf $nonex-buf;

    method PlugInit() {
        #pull the domain from the url
        $!buster.url ~~ /https?\:\/\/(<-[ / ]>+)/;
        $dom = $/[0].Str;

        $!buster.curlopts('nobody'=> 0); #change back to GETs
        my $client = curl.new(|$!buster.curlopts);
        $client.perform();
        $base-buf = $client.buf;

        #nonex subdomain
        $client.set-header('Host'=>wildstr~'.'~$dom);
        $client.perform();
        $nonex-buf = $client.buf;
    }
    method ThreadInit() {
        #instantiate libcurl
        return %(client => curl.new(|$!buster.curlopts) );
    }
    method Process(Str $word, :%opt) {
        my $client := %opt<client>;
        #update our Host header & send request
        my $host = $word~'.'~$dom;
        $client.set-header('Host'=>$host);
        $client.perform;

        my $Hit=False;
        my $t = $client.buf;
        $Hit = True if $t != $base-buf && $t != $nonex-buf; #hit if different body
        return Result.new(Entity=>$host, :$Hit);
    }
}
```

## License

See the LICENSE file.
