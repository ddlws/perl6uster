use perl6uster::common;
use perl6uster::options;
use perl6uster::keygrab;
use Term::Choose;
use MONKEY-SEE-NO-EVAL;

role perl6uster-plugin {...}

class Result {
    has Str $.Entity='';
    has int $.Status=0;
    has $.Extra;
    has int $.Size=0;
    has Bool $.Hit=False;
}
class Buster {
    has Channel $.word-chan .= new;
    has Channel $.result-chan .= new;
    has int $.num-words;
    has atomicint $.words-done = 0; #⚛
    has Options $.o;
    has OptionsHTTP $.httpo;
    has $.plugin;
    has $.plugclass;
    has Regex @.rx-filters;
    has Str @.str-filters;
    has Block @.rx-mutators;
    has Str @.str-mutators;
    has Bool $!sndorig;
    has Bool $.paused is rw = False;
    has Lock $!evalthis .= new;
    has key-grabber $!grabber;

    submethod TWEAK(:$filt,:$!sndorig,:$mut,*%opts) {

        #jump through hoops to make plugins work.
        given %opts<mode> {
            when 'dir' {
                unless %opts<u> || %opts<help> {dwd('A URL(-u) is required',$?FILE, $?LINE) };
                require perl6uster::DIR;
                $!plugclass=::('plug-dir');
                succeed;
            }
            when 'dns' {
                unless %opts<d> || %opts<help> {dwd('A domain(-d) is required',$?FILE, $?LINE) }
                unless %opts<R> || %opts<help> {dwd('A DNS server(-R) is required',$?FILE, $?LINE) }
                require perl6uster::DNS;
                $!plugclass=::('plug-dns');
                succeed;
            }
            when 'vhost' {
                unless %opts<u> || %opts<help> {dwd('A URL(-u) is required',$?FILE, $?LINE) }
                require perl6uster::VHOST;
                $!plugclass=::('plug-vhost');
            }
            default {
                unless %opts<mode>.IO ~~ :r {
                        dwd("{%opts<mode>} is not readable!", $?FILE,$?LINE) }
                $!plugclass=EVAL(%opts<mode>.IO.slurp);
                unless $!plugclass ~~ perl6uster-plugin { dwd('rtfm',$?FILE,$?LINE) }
            }
        }
        #earliest we can call plugin.help
        if %opts<help> { $!plugclass.?Help(); exit 0; }
        $!o .= new(|%opts);
        $!httpo.=new(|%opts);
        my %tmp = buster => self;
        %tmp.append(%opts);
        $!plugin = $!plugclass.new(|%tmp);
        ##compile regex supplied on the commandline.
        if $filt {
            for 0..($filt.elems-1) {
                if self.check-rx($filt[$_]) {
                    @!rx-filters.push( "$filt[$_]".EVAL );
                    @!str-filters.push( "$filt[$_]" );
                }
                else {dwd("'$filt[$_]' - failed to compile.",$?FILE,$?LINE); }
            }
        }
        ##now check mutators.
        if $mut {
            for 0..($mut.elems-1) {
                if self.check-mut($mut[$_]) {
                    @!rx-mutators.push(
                        ('-> $cand is rw { $cand ~~ '~"{$mut[$_]}"~'; $cand }').EVAL);
                    @!str-mutators.push( $mut[$_] );
                }
                else {dwd(
                    "'$mut[$_]' - failed to compile.",$?FILE,$?LINE); }
            }
        }
        #wordlist is a regular file. starts thread to send lines over the word channel
        if $!o.wordlist {
            start {
                my $malformedutf8 = $!o.wordlist.IO.open(:r,:enc('utf8-c8'));
                $!num-words = $malformedutf8.IO.lines.elems;
                for $malformedutf8.lines { $!word-chan.send($_) }
                $!word-chan.close();
                $malformedutf8.close;
            }
        }
        #wordlist is stdin. makes a supply of stdin and emits lines over word channel.
        else {
            if ?$!paused {
                dwd("Can't use the menu when piping wordlist over stdin", $?FILE,
                        $?LINE);
            }
            $!word-chan = supply {
                whenever start $*IN.Supply {
                    whenever .lines {.emit}
                }
            }.Channel;
        }
        $!grabber .= new if $*IN.t;#starts the keygrabber if stdin is a tty
        if ?$!paused { self.bustus-interruptus }
    }

    #This is the main loop for worker threads. filters applied here
    method worker(:%opt) {
        WORKLOOP:
        loop {
            while $!paused == True { sleep .5; }
            sleep $!o.idelay if $!o.idelay; #this will delay before the first request.
            my $word = $!word-chan.receive;
            $!words-done⚛++;

            #skip word if any filters match
            for @!rx-filters { next WORKLOOP if $word ~~ $_ }

            my @results;
#`(behavior:
- if no mutators change word, send the word regardless of sndorig
- if mutators change word, only send original if sndorig

)
            if ?@!rx-mutators {
                my @words;
                my $had-effect=False;
                for @!rx-mutators {
                    my $new-word = $word;
                    #one day, EVAL will be thread safe
                    $!evalthis.protect( { $_($new-word);});
                    if $new-word ne $word { @words.push: $new-word; $had-effect=True }
                }
                @words.push($word) if $!sndorig || ($had-effect == False);
                for @words { @results.append(|$!plugin.Process($_,:%opt)) }
            }
            #process the original word
            else{ @results.append(|$!plugin.Process($word,:%opt)) }

            for @results { $!result-chan.send($_) if $_ ~~ Result; }

            #flow control. stop the loop when out of words
            CATCH{when  X::Channel::ReceiveOnClosed {last WORKLOOP;}}
        }
    }
    #worker thread that waits for results and prints them
    method resultWorker(){
        my $fh;
        if $!o.outfile { $fh = $!o.outfile.IO.open(:rw); }
        my Result $res;
        RESLOOP:
        loop {
            $res = $!result-chan.receive;
            if $res.Hit || $!o.verbose {
                my $out = $!plugin.ResultToString($res);
                if $!o.outfile { $fh.put: $out;}
                self.clearProgress();
                say $out;
            }
            #flow control
            CATCH{ when X::Channel::ReceiveOnClosed {last RESLOOP;}}
        }
    }
    #updates the progress display. 1 second ticks
    method progressWorker(){
        loop {
            while $!paused == True { sleep 1; }
            sleep 1;
            self.clearProgress();

            if ! ?$!o.wordlist {$*ERR.printf("Progress: %d words done",$!words-done);}
            elsif $!num-words > 0 {
                $*ERR.printf("Progress: %d / %d (%3.2f%%)", $!words-done, $!num-words,
                        $!words-done *100 / $!num-words);
            }
        }
    }
    ##clears the line and resets cursor
    method clearProgress(){
        $*ERR.print(cl);
        $*ERR.print(stl);
    }
    #prints generic config options
    method PrintConfig() {
        $!plugin.?PrintConfig();
        sprintf(spc('[+] Mode')~": %s", $!o.mode).note;
        sprintf(spc('[+] Threads')~": %d", $!o.threads).note;
        my $wordlist = "stdin (pipe)";
        if $!o.wordlist {$wordlist = $!o.wordlist;}
        sprintf(spc('[+] Wordlist')~": %s", $wordlist).note;
        if $!o.noStatus {sprintf(spc('[+] No status')~": True").note;}
        if $!o.noProgress {sprintf(spc('[+] No progress')~": True").note;}
        if $!o.verbose {sprintf(spc('[+] Verbose')~": True").note;}
        if $!o.delay > 0 {sprintf(spc('[+] Delay')~": %d", $!o.delay).note;}
        if @!str-filters { sprintf(spc('[+] Filters')~
                ': '~@!str-filters.join(' , ')).note; }
        if @!str-mutators {
            sprintf(spc('[+] Mutators')~': '~@!str-mutators.join(' , ')).note;
            sprintf(spc('[+] Send original')~": {$!sndorig}").note;
        }
    }
    #starts the keygrabber & registers callback
    method setupkeygrab() { $!grabber.startlisten(&{self.bustus-interruptus}) }
    #callback for keygrabber
    method bustus-interruptus() is export {
        $!paused=True;
        my @options = ["Add filter", "Add mutator", "List filters", "List mutators",
                "Resume busting" ];
        sleep 1; #sucks, but it's to avoid the progress printer mangling the menu
        loop {
            my $chosen = choose(@options, :layout(2), :prompt("\nOptions:\n") );
            given $chosen {
                when "Add filter" {self.addFilter()}
                when "Add mutator" {self.addMutator()}
                when "List filters" { .say for @!str-filters }
                when "List mutators" { .say for @!str-mutators }
                when "Resume busting" { self.resume-busting(); last;}
            }
        }
    }
    #start scanning again & restart keygrabber
    method resume-busting() {
        $!paused=False;
        self.setupkeygrab();
    }
    #add filter through the menu
    method addFilter() {
        my $filt = prompt("\nEnter a p6 regex. Matches will be "~
            ~"skipped. Outer delimeters required. e.g. / perl[6||b]uster / \n> ");
        if self.check-rx($filt) {
            @!rx-filters.push( "$filt".EVAL );
            @!str-filters.push( "$filt" );
        }
    }
    #add mutator through the menu
    method addMutator() {
        my $mut = prompt("\nEnter a s/// or tr/// mutator. e.g. s/this/that/ or "~
                "tr/a/b/ \n> ");
        if self.check-mut($mut) {
            @!rx-filters.push( "$mut".EVAL );
            @!str-filters.push( "$mut" );
        }
    }
    #Compiler errors are fatal, so test on a child process and check the exitcode.
    method check-rx(Str $rgx) {
        my $result = run $*EXECUTABLE.absolute(), '-e', "'TESTSTRING123' ~~ $rgx;",
            :out, :err;
        if $result.exitcode == 0 { return True }
        else {
            note "Invalid regex: $rgx failed to compile";
            note $result.err.slurp(:close);
            return False;
        }
    }
    #verify it's a tr/// or s/// string and see if it compiles
    method check-mut(Str $mut) {
        #/^\s*[tr||s][\:\w+]* \/ .*? <!after '\'> \/ .*? <!after '\'> \/\s* $/
        if $mut ~~ /^\s*[tr||s][\:\w+]* \/
                    .*? <!after '\'> \/
                    .*? <!after '\'> \/\s* $/
        {
            my $result = run $*EXECUTABLE.absolute(), '-e',
                    'my $q='~"'TESTSTRING123'"~'; $q ~~ '~"{$mut};", :out, :err;
            if $result.exitcode == 0 { return True }
            else {
                note "Invalid code: $mut failed to compile";
                note $result.err.slurp(:close);
                return False;
            }
        }
        else {
            note "Only 'tr///' and 's///' are supported at this time.";
            return False;
        }
    }

    #helpers for plugin writing
    #general options
    method mode() { return $!o.mode }
    method threads() { return $!o.threads }
    method wordlist() { return $!o.wordlist }
    method outfile() { return $!o.outfile }
    method noStatus() { return $!o.noStatus }
    method noProgress() { return $!o.noProgress }
    method quiet() {return $!o.quiet }
    method wildcardForced() {return $!o.wildcardForced }
    method verbose() { return $!o.verbose }
    method delay() { return $!o.delay }
    method idelay() { return $!o.idelay }
    #http options
    method password() {return $!httpo.password}
    method url() { return $!httpo.URL ; }
    method userAgent() {return $!httpo.userAgent}
    method username() {return $!httpo.username}
    method proxy() {return $!httpo.proxy}
    method cookies() {return $!httpo.cookies}
    method httpheaders() {return $!httpo.httpheaders}
    method timeout() {return $!httpo.timeout}
    method followRedirect() {return $!httpo.followRedirect}
    method insecureSSL() {return $!httpo.insecureSSL}
    method auth() {return $!httpo.auth}
    method token() {return $!httpo.token}
    multi method curlopts() { return $!httpo.curlopts; }
    multi method curlopts(Pair $p) { $!httpo.curlopts{$p.key}=$p.value }
}
#Defines the plugin interface.
role perl6uster-plugin {
    has Buster $!buster;
    submethod BUILD(Buster :$!buster){}

    #takes the candidate word and does something with it. requests, etc.
    method Process(Str $word, :%opt) {...}

    #takes a Result object and formats/prints results
    method ResultToString(Result $r) { return $r.Entity }

    #plugin initialization
    method PlugInit() { return }

    #called for each thread. use it to initialize thread-specific resources
    method ThreadInit() { return }

    #prints plugin-specific configuration info
    method PrintConfig() { return }

    #print plugin help when '-h' is passed on cmdline
    method Help() { return }
}
