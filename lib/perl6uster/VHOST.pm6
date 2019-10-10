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
