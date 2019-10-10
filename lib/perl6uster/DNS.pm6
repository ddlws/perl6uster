use perl6uster::buster;
use perl6uster::common;
use Net::DNS;

class plug-dns does perl6uster-plugin {
    has Str $!domain;
    has Str $!resolver;
    has Bool $!showCNAME;
    has Bool $!showIP;
    has Net::DNS $!client;
    has @!wcIPs;
    has Bool $!isWild=False;

    submethod TWEAK(:d(:$!domain),                      :R(:$!resolver),
                    Bool :C(:$!showCNAME)=False,        Bool :i(:$!showIP)=False )
        { $!client .= new($!resolver) }

    method PlugInit() {
        my @test;
        #check base domain
        unless $!buster.quiet {
            @test = $!client.lookup-ips($!domain);
            unless @test {
                    note "[-] Base domain '$!domain' did not resolve." }
        }
        #check for wildcards
        @test = $!client.lookup-ips(wildstr()~$!domain);
        if @test {
            unless $!buster.wildcardForced { dwd("Force processing of Wildcard
                    responses with the '-fw' switch.",$?FILE,$?LINE) }
            for @test { $_.Str ==> @!wcIPs }
        }
    }
    method Process($word, :%opt) {
        my @result;
        my $subd = $word~'.'~$!domain;
        my @resp = $!client.lookup-ips($subd);
        if @resp {
            unless $!isWild || @!wcIPs ∩ (@resp>>.Str) {
                @result.push(Result.new( Entity=>$subd, Hit=>True,
                        Extra=> $!showIP ?? @resp>>.Str.join(', ') !! $!showCNAME ??
                        $!client.lookup('CNAME',$subd)>>.name>>.join('.') !! '' ));
            }
        }
        elsif $!buster.verbose {
            @result.push(Result.new(Entity=>$subd,Hit=>False));
        }
        return @result;
    }

    method ResultToString(Result $r) {
        my Str $retstr='';
        if ?$r.Hit { $retstr ~= "Found: " }
        else { $retstr ~= "Missed: " }

        #build the string
        $retstr ~= $r.Entity~' ';
        if $!showIP || $!showCNAME { $retstr ~= $r.Extra }
        return $retstr;
    }

    method PrintConfig() {
        sprintf(spc('[+] Domain')~": %s", $!domain).note;
        sprintf(spc('[+] Resolver')~": %s", $!resolver).note;
        sprintf(spc('[+] Show CNAME')~": %s", $!showCNAME).note;
        sprintf(spc('[+] Show IPs')~": %s", $!showIP).note;
        sprintf(spc('[+] Timeout')~": %s", $!buster.timeout).note;
    }

    method Help() {
        print Q:c:to/END/;
        DNS mode flags:
          -c                        Show CNAME records (cannot be used with '-i' option)
          -d=<string>               The target domain
          -h                        help for dns
          -i                        Show IP addresses
          -R=<string>               Use custom DNS server (ip address)
          -to                       DNS resolver timeout (default 1s)
        END
    }
}

#method ThreadInit() {}

