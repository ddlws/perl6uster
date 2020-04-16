use perl6uster::buster;
use perl6uster::common;
use perl6uster::curl;

class plug-dir does perl6uster-plugin {
    has Str @.exts;
    has int @.stat-codes;
    has Bool $!scbl=False; #statcode blacklist
    has Bool $!useSlash=False;
    has Bool $!include-length=False;
    has Bool $!expanded=False;
    has Str $!target;
    has Str $!url-dom;
    has Str $!slash='';
    has Bool $!backups=False;
    has Bool $!extonly=False;
    has Bool $!uenc=False;

    #not an attr because it's used in a regex
    my Str @src-extensions = <php asp>;

    submethod TWEAK(Buster :$!buster,
                Str :x(:$extensions),           :b(:$blscodes),
                Str :s(:$scodes)='200,204,301,302,307,401,403',
                Bool :f(:$!useSlash),           Bool :l(:$!include-length),
                Bool :e(:$!expanded),           *%opts,
                Bool :bk(:$!backups),            Bool :xo(:$!extonly),
                Bool :ue(:$!uenc)
                )
    {
        unless $!buster.url {dwd('A URL is required',$?FILE, $?LINE) }
        $!buster.url ~~ /(https?\:\/\/<-[ / ]>+)(\/.*)?/;
        dwd("Fix the URL: {$!buster.url}",$?FILE, $?LINE) unless $/.elems==2;
        $!url-dom=$/[0].Str;
        $!target = $/[1].Str.starts-with('/') ?? $/[1].Str !! '/'~$/[1].Str;
        $!slash = '/' if $!useSlash;

        #parse extensions
        if ?$extensions {
            my $ext = $extensions;
            $ext ~~ s:s:g/\s//; #remove spaces
            $ext ~~ s:s:g/\,\.//; #remove leading dots
            $ext.split(',').eager ==> @!exts;
        }
        #status-codes
        my $codes;
        if $blscodes { $codes = $blscodes; $!scbl=True; }
        else { $codes = $scodes }
        $codes ~~ s:s:g/\s//; #remove spaces
        $codes.split(',').eager>>.Numeric ==> @!stat-codes;
    }

    method PlugInit() {
        #test client
        my $client = curl.new(|$!buster.curlopts);
        my $resp = self.GetRequest($!target,$client);
        #check for wildcard responses
        $resp = self.GetRequest( $!target~wildstr,$client );
        if @!stat-codes (cont) $resp.Status && ! $!scbl {
            note(sprintf("[-] Wildcard response found: %s => %d", $resp.Entity,
                $resp.Status));
            unless $!buster.wildcardForced {
                dwd("Force processing of Wildcard responses with the '-fw' "~
                        "switch.",$?FILE,$?LINE);
            }
        }
    }

    method Process(Str $word is rw, :%opt) {
        #return Nil if $word ~~ /"\t"/; #tabs were causing too many casualties
        $word ~~ s:g/(<-alnum>)/$0.ord.fmt("%%%02X")/ if $!uenc;
        my Result @resp;
        my Result $tmp;
        unless $!extonly {
            $tmp = self.GetRequest($!target~$word~$!slash,%opt<client>);
            @resp.push($tmp);
        }
        #extensions
        for @!exts {
            $tmp = self.GetRequest($!target~$word~'.'~$_, %opt<client>);
            @resp.push: $tmp;
        }
        #check for backup/temp files if we hit something with the right extensions
        if $!backups {
            for @resp {
                if $_.Entity ~~ / \. {@src-extensions} / {
                    $tmp = self.GetRequest($!target~$_.Entity~'~', %opt<client>);
                    @resp.push: $tmp;
                }
            }
        }
        return @resp;
    }
    method GetRequest($target, curl $client --> Result) {
        $client.setopt(request-target => $target);
        $client.perform;
        my $cl = $client.get-header('Content-Length');
        my $rc = $client.response-code;
        my $hit=False;
        if $!scbl { $hit = True unless @!stat-codes (cont) $rc }
        else { $hit = @!stat-codes (cont) $rc ?? True !! False; }

        return Result.new(
                Size=> ?$cl ?? $cl.Numeric !! 0,
                Status=>$rc,
                Entity=>$target,
                Hit=> $hit );
    }
    method ResultToString(Result $r) {
        my Str $retstr='';
        if @!stat-codes (cont) $r.Status {$retstr~= "Found: ";}
        else {$retstr ~= "Missed: ";}

        if $!expanded {$retstr ~= $!url-dom~$r.Entity;}
        else {$retstr ~= $r.Entity;}

        unless $!buster.noStatus {$retstr ~= sprintf(" (Status: %d)",$r.Status);}
        if $!include-length {$retstr ~= " [Size: "~$r.Size~"]";}
        return $retstr;
    }

    method ThreadInit() {
        return %(client => curl.new(|$!buster.curlopts) );
    }

    #prints plugin options
    method PrintConfig() {
        sprintf(spc('[+] Url/Domain')~": %s", $!buster.url).note;
        sprintf(spc('[+] Status codes')~": %s", @!stat-codes.join(',')).note;
        sprintf(spc('[+] User Agent')~": %s", $!buster.userAgent).note;
        sprintf(spc('[+] Timeout')~": %s", $!buster.timeout).note;
        if $!buster.proxy {
            sprintf(spc('[+] Proxy')~": %s", $!buster.proxy).note;
        }
        if $!buster.cookies {
            sprintf(spc('[+] Cookies')~": %s", $!buster.cookies).note;
        }
        if $!include-length {sprintf(spc('[+] Show length')~": true").note;}
        if $!buster.username {sprintf(spc('[+] Auth User')~
                            ": %s", $!buster.username).note;}
        if @!exts.elems > 0 {sprintf(spc('[+] Extensions')~
                            ": %s", @!exts.join(',')).note;}
        if $!useSlash {sprintf(spc('[+] Add Slash')~": true").note;}
        if $!buster.followRedirect {
            sprintf(spc('[+] Follow Redir')~": true").note;
        }
        if $!expanded {sprintf(spc('[+] Expanded')~": true").note;}
    }
    #prints plugin help
    method Help() {
        print Q:c:to/END/;
        Dir mode flags:
          -b=<string>              Negative status codes (will override statuscodes if set)
          -bk                      Automatically check for backup/temp files when source files are hit (php,asp)
          -e                       Expanded mode, print full URLs
          -f                       Append '/' to each request
          -l                       Include the length of the body in the output
          -s=<string>              Positive status codes
                                     (default "200,204,301,302,307,401,403")
          -ue                      URL encode the request
          -x=<string>              File extension(s) to search for
          -xo                      Extensions only/no bare words. All requests will have an extension.
        END
    }
}
