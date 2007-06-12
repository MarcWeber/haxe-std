package neko.vm;

class Os {

	public static function isMainThread() {
		return _is_main_thread();
	}

	public static function loop() {
		_loop();
	}

	public static function stopLoop() {
		_stop_loop();
	}

	public static function sync( f : Void -> Void ) {
		_sync(f);
	}

	public static function syncResult<T>( f : Void -> T ) : T {
		if( isMainThread() )
			return f();
		var l = new Lock();
		var tmp = null;
		var exc = null;
		_sync(function() {
			try {
				tmp = f();
			} catch( e : Dynamic ) {
				exc = { v : e };
			}
			l.release();
		});
		l.wait();
		if( exc != null )
			throw exc.v;
		return tmp;
	}

	static var _is_main_thread = neko.Lib.load("os","os_is_main",0);
	static var _loop = neko.Lib.load("os","os_loop",0);
	static var _stop_loop = neko.Lib.load("os","os_stop_loop",0);
	static var _sync = neko.Lib.load("os","os_sync",1);

}