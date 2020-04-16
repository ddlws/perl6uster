use LibCurl::Easy;
use perl6uster::common;

class curl {
    has %!hdr;
    has LibCurl::Easy $.easy handles <buf clear-header content error get-header getinfo
            primary-ip receiveheaders response-code setopt success version
            version-info>;

    method perform() {
        $!easy.perform;
        unless ?$!easy.response-code { dwd( "No response code for "~
                $!easy.getinfo('effective-url'),$?FILE,$?LINE) }
        CATCH {
            when X::LibCurl {
                #if $_.Int() == 1 { $!easy.setopt('nobody'=>0); self.perform; }
                dwd("libcurl threw\nErrno $_.Int() : $_\nError: {$!easy.error}",
                        $?FILE,$?LINE);
            }
            say $_;
            dwd('Something went wrong.',$?FILE,$?LINE);
        }
    }

    multi method set-header(%header) {
        for %header.keys { %!hdr{$_} = %header{$_} }
        self.set-header();
    }
    multi method set-header(Pair $p) {
        %!hdr{$p.key} = $p.value;
        self.set-header();
    }
    multi method set-header() {
        self.clear-header;
        $!easy.set-header(|%!hdr);
        return self
    }
    multi method delete-header(Str $header) {
        %!hdr{$header}:delete;
        self.set-header();
        return self
    }
    multi method delete-header() {
        %!hdr = %();
        self.set-header();
        return self
    }

    submethod BUILD(:%!hdr, |opts) {
        $!easy = LibCurl::Easy.new(|opts);
        $!easy.set-header(|%!hdr);
    }
}
