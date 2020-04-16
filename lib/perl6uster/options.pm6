use perl6uster::common;

#universal options
class Options {
    #general options
    has Str $.mode;
    has int $.threads;
    has Str $.wordlist is rw;
    has Str $.outfile;
    has Bool $.noStatus;
    has Bool $.noProgress;
    has Bool $.quiet;
    has Bool $.wildcardForced;
    has Bool $.verbose;
    has str $.delay;
    has int $.idelay;

    #validate stuff
    submethod TWEAK(*%opts) {
        return if %opts<help>;
        my @errors;
        #-t
        if $!threads < 0 {
            #note sprintf("Threads (-t): Invalid value: %d",$!threads); $valid=False;}
            @errors.push(sprintf("Threads (-t): Invalid value: %d",$!threads));
        }
        #-w
        if ?$!wordlist {
            unless $!wordlist.IO ~~ :e {
                @errors.push(sprintf("Wordlist (-w): File does not exist: %s",$!wordlist));
            }
            unless $!wordlist.IO ~~ :r {
                @errors.push(sprintf("Wordlist (-w): File is not readable: %s",
                        $!wordlist));
            }
        }
        #-o
        if $!outfile {
            try { $!outfile.IO.open(:w) }
            if $! {
                @errors.push(sprintf("Outfile (-o): File is not writable: '%s'",
                        $!outfile));
            }
        }
        #-delay
        if $!delay -> $_ { $_ ~~ / (\d+[\.\d+]?)(ms)? /;
            if $/[1] { $!idelay = $/[0].Str.Numeric / 1000 }
            else { $!idelay = $/[0].Str.Numeric }
        }
        if @errors {
            note "\nErrors:\n";
            .note for @errors;
            dwd("Fix the errors and try again.",$?FILE,$?LINE);
        }
    }
}
#prompts for a password. doesn't echo keypresses
sub askpass() {
        my $TTY;
        ENTER {$TTY = open("/dev/tty"); shell "stty -echo"; }
        LEAVE {shell "stty echo"; close($TTY); }
        print "[?] Auth Password: \n";
        return $TTY.read().decode('latin1');
}

#Common HTTP options
class OptionsHTTP {
	has Str $.password is rw;
	has Str $.URL;
	has Str $.userAgent;
    has Str $.username;
	has Str $.proxy;
    has Str $.cookies;
	has %.httpheaders is rw;
	has Int $.timeout;
	has Bool $.followRedirect;
	has Bool $.insecureSSL;
    has Str $.auth;
    has Str $.token;
    has Str $.HTTPmethod;
    has %.curlopts is rw;

    #pasted here so we can setup options without importing again.
    enum CURLAUTH (
    CURLAUTH_NONE         => 0,
    CURLAUTH_BASIC        => 1,
    CURLAUTH_DIGEST       => 1 +< 1,
    CURLAUTH_GSSNEGOTIATE => 1 +< 2,
    CURLAUTH_NTLM         => 1 +< 3,
    CURLAUTH_DIGEST_IE    => 1 +< 4,
    CURLAUTH_NTLM_WB      => 1 +< 5,
    CURLAUTH_BEARER       => 1 +< 6,
    CURLAUTH_ONLY         => 1 +< 31,
    );
    constant CURLAUTH_ANY = +^CURLAUTH_DIGEST_IE;

    submethod TWEAK(Str :u(:$!URL),                 Str :c(:$!cookies),
                    Str :U(:$!username),            Str :P(:$!password),
                    Str :a(:$!userAgent),           Str :p(:$!proxy),
                    Int :to(:$!timeout)=10,         Bool :r(:$!followRedirect)=False,
                    Bool :k(:$!insecureSSL)=False,  :H(:$argheaders),
                    Bool :h($help),                 Str :$!auth,
                    Str :T(:$!token),               Str :meth(:$!HTTPmethod)='head'
                    )
    {

        #take any header arguments and put them into a hash
        if $argheaders {
            #headers aren't added without the 'eager' prefix.
            eager map({%!httpheaders{$_[0]}=$_[1]},
                    $argheaders.list>>.split(':',2)>>.trim);
            %!curlopts<hdr> = %!httpheaders;

        }
        if ?$!URL {
            unless $!URL.ends-with('/') {$!URL = sprintf("%s/",$!URL) }
            %!curlopts<URL>=$!URL;
        }
        #set libcurl options
        %!curlopts<failonerror> = 0;


        #handle command line args
        #-f
        unless ?$!followRedirect {%!curlopts<followlocation> = 0;}
        #-c
        if ?$!cookies {%!curlopts<cookie> = $!cookies}
        #-a
        unless ?$!userAgent { $!userAgent = 'perl6uster/'~::('$VERSION')}
        %!curlopts<useragent> = $!userAgent;
        #-p
        if ?$!proxy {
            unless $!proxy ~~ /https?||socks[4a?||5h?]\/\// {
                dwd("Proxy string must specify scheme.  'http://', 'socks4://', etc",
                        $?FILE,$?LINE);
            }
            %!curlopts<proxy>=$!proxy;
        }
        #-k
        if ?$!insecureSSL  {%!curlopts.push((
                ssl-verifyhost => 0,
                ssl-verifypeer => 0 ))}
        #-to
        if ?$!timeout  { $!timeout ~~ /(\.?\d+[\.\d+]?)(ms)?/;
            if $/[1] { %!curlopts<timeout-ms> = $/[0].Str.Numeric }
            else { %!curlopts<timeout> = $/[0].Str.Numeric }
        }
        #-U
        if ?$!username && not $!password { $!password = askpass() }

        #-meth
        given $!HTTPmethod.fc {
            when 'get'.fc {%!curlopts<nobody> = 0}
            when 'head'.fc {%!curlopts<nobody> = 1}
        }
        #auth stuff
        if ?$!auth {
            given $!auth {
                when /:i basic/ { %!curlopts.append(httpauth => CURLAUTH_BASIC,
                    username => $!username,
                    password => $!password);
                }
                when /:i bearer/ { %!curlopts.append(httpauth => CURLAUTH_BEARER,
                    xoauth2-bearer => $!token); }
                when /:i digest/ {
                    %!curlopts.append(httpauth => CURLAUTH_DIGEST,
                    username => $!username,
                    password => $!password);
                }
                when /:i ntlm / { %!curlopts.append(httpauth => CURLAUTH_NTLM,
                    username => $!username,
                    password => $!password);
                }
                #`(when / :i negotiate/ {
                    %!curlopts.append(httpauth => CURLAUTH_GSSNEGOTIATE,
                    );
                })
            }
        }
    }
}
