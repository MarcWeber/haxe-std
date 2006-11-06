/*
 * Copyright (c) 2005, The haXe Project Contributors
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
package neko.net;

enum RemotingError {
	ReadError;
	InvalidMessage;
}

class RemotingBuffer {

	public static var START_SIZE = 256;
	public static var MAX_SIZE = 4096;

	var buffer : String;
	var bufpos : Int;
	var lastpos : Int;
	var msglen : Int;
	var sock : neko.net.Socket;
	var lastread : Float;

	public function new(s) {
		sock = s;
		bufpos = 0;
		lastpos = 0;
		lastread = neko.Sys.time();
		buffer = neko.Lib.makeString(START_SIZE);
	}

	public function lastRead() {
		return lastread;
	}

	public function bufferData() {
	    return buffer.substr(lastpos,bufpos - lastpos);
	}

	public function onData( data : String ) {
	}

	public function onXmlData( data : String ) {
	}

	public function read() {
		var buflen = buffer.length;
		var len = try sock.input.readBytes(buffer,bufpos,buflen-bufpos) catch( e : Dynamic ) { if( e == neko.io.Error.Blocked ) return; 0; };
		if( len == 0 )
			throw ReadError;
		lastread = neko.Sys.time();
		bufpos += len;
		while( process(len) ) {
		}
		if( bufpos == buflen ) {
			// copy/expand buffer
			if( lastpos != 0 ) {
				var bytes = bufpos-lastpos;
				neko.Lib.copyBytes(buffer,0,buffer,lastpos,bytes);
				lastpos = 0;
				bufpos = bytes;
			} else {
				if( buflen * 2 > MAX_SIZE )
					throw InvalidMessage; // can only happens for Xml messages
				var b2 = neko.Lib.makeString(buflen * 2);
				neko.Lib.copyBytes(b2,0,buffer,0,bufpos);
				buffer = b2;
			}
		}
	}

	function decodeMessageLength() {
		// message starting with < : XML
		if( buffer.charCodeAt(lastpos) == 60 )
			return -1;
		var c1 = decodeChar(buffer.charCodeAt(lastpos));
		var c2 = decodeChar(buffer.charCodeAt(lastpos+1));
		if( c1 == null || c2 == null )
			throw InvalidMessage;
		return (c1 << 6) | c2;
	}

	function decodeChar(c) {
		// A...Z
		if( c >= 65 && c <= 90 )
			return c - 65;
		// a...z
		if( c >= 97 && c <= 122 )
			return c - 97 + 26;
		// 0...9
		if( c >= 48 && c <= 57 )
			return c - 48 + 52;
		// +
		if( c == 43 )
			return 62;
		// /
		if( c == 47 )
			return 63;
		return null;
	}

	function process( nbytes ) {
		var av_bytes = bufpos - lastpos;
		if( av_bytes < 2 )
			return false;
		if( msglen == null )
			msglen = decodeMessageLength();
		var isxml = false;
		if( msglen == -1 ) {
			// wait for \0
			var i = nbytes;
			while( i > 0 ) {
				if( buffer.charCodeAt(bufpos - i) == 0 )
					break;
				i -= 1;
			}
			if( i == 0 )
				return false;
			msglen = av_bytes - i;
			isxml = true;
		} else {
			if( av_bytes < msglen )
				return false;
			lastpos += 2;
			msglen -= 3;
		}
		var msg = buffer.substr(lastpos,msglen);
		lastpos += msglen + 1;
		msglen = null;
		if( lastpos == bufpos ) {
			lastpos = 0;
			bufpos = 0;
		}
		if( isxml )
			onXmlData(msg);
		else
			onData(msg);
		return true;
	}

}