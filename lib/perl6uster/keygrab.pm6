use NativeCall;
use Term::termios;
sub getchar returns int32 is native { * }

class key-grabber {
    has Supply $!keysupply;
    has Tap $!keytap;
    has Supplier $!tty;
    has Bool $!stop=False;
    has Term::termios $!termsettings;
    has Promise $.listener;

    submethod TWEAK {
        $!tty .= new;
        $!termsettings .= new(:fd($*IN.native-descriptor)).getattr;
    }
    #listens until first keypress, then calls the callback. won't restart itself
    method startlisten(&cb) is export {
        $!keysupply = $!tty.Supply.on-close: { $!stop=True };
        $!stop=False;
        $!keytap = $!keysupply.tap( -> $k { if $k eq 'p' {$!keytap.close; cb} });
        $!listener = start {
            my $char;
            until $!stop {
                $!termsettings.unset_lflags('ICANON');
                $!termsettings.unset_lflags('ECHO');
                $!termsettings.setattr(:NOW);
                $char = getchar;
                $!termsettings.set_lflags('ECHO');
                $!termsettings.set_lflags('ICANON');
                $!termsettings.setattr(:NOW);
                $!tty.emit($char.chr);
            }
        }
    }

    #call to stop listener before a keypress and get back control of the terminal
    method stoplisten() is export {
        $!keytap.close;
        $!listener.break;
        $!termsettings.set_lflags('ECHO');
        $!termsettings.set_lflags('ICANON');
        $!termsettings.setattr(:NOW);
    }
}
