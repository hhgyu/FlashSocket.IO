package com.pnwrain.flashsocket
{
	import com.adobe.serialization.json.JSON;
	import com.demonsters.debugger.MonsterDebugger;
	import com.jimisaacs.data.URL;
	import com.pnwrain.flashsocket.events.FlashSocketEvent;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.system.Security;
	import flash.utils.Timer;
	
	public class FlashSocket extends EventDispatcher implements IWebSocketWrapper
	{
		protected var debug:Boolean = true;
		protected var callerUrl:String;
		protected var socketURL:String;
		protected var webSocket:WebSocket;
		
		//vars returned from discovery
		public var sessionID:String;
		protected var heartBeatTimeout:int;
		protected var connectionClosingTimeout:int;
		protected var protocols:Array;
		
		//hold over variables from constructor for discover to use
		private var domain:String;
		private var protocol:String;
		private var proxyHost:String;
		private var proxyPort:int;
		private var headers:String;
		private var timer:Timer;
		private var channel:String = "";
		
		private var ackRegexp:RegExp = new RegExp('(\\d+)\\+(.*)');
		private var ackId:int = 0;
		private var acks:Object = { };
		
		public function FlashSocket( domain:String, protocol:String=null, proxyHost:String = null, proxyPort:int = 0, headers:String = null)
		{
			var httpProtocal:String = "http";
			var webSocketProtocal:String = "ws";
			
			var URLUtil:URL = new URL(domain);
			if (URLUtil.protocol == "https") {
				httpProtocal = "https";
				webSocketProtocal = "wss";
			}
			
			//if the user passed in http:// or https:// we want to strip that out
			//if(domain.indexOf('://')>=0){
				domain = URLUtil.host;
			//}

			this.socketURL = webSocketProtocal+"://" + domain + "/socket.io/1/flashsocket";
			//this.socketURL = domain + "/socket.io/1/flashsocket";
			this.callerUrl = httpProtocal+"://mobile-games.jimib.co.uk/pong.swf";
			
			this.domain = domain;
			this.protocol = protocol;
			this.proxyHost = proxyHost;
			this.proxyPort = proxyPort;
			this.headers = headers;
			this.channel = URLUtil.pathname || "";
			
			if(this.channel && this.channel.length > 0 && this.channel.indexOf("/") != 0){
				this.channel = "/" + this.channel;
			}
			
			var r:URLRequest = new URLRequest();
			var now:Date = new Date();
			r.url = httpProtocal+"://" + domain + "/socket.io/1/?time=" + now.getTime();
			r.method = URLRequestMethod.POST;
			var ul:URLLoader = new URLLoader(r);
			ul.addEventListener(Event.COMPLETE, onDiscover);
			ul.addEventListener(HTTPStatusEvent.HTTP_STATUS, onDiscoverError);
			ul.addEventListener(IOErrorEvent.IO_ERROR , onDiscoverError);

		}
		
		protected function onDiscover(event:Event):void{
			MonsterDebugger.trace(this, "onDiscover: "+event.type);
			
			var response:String = event.target.data;
			var respData:Array = response.split(":");
			sessionID = respData[0];
			heartBeatTimeout = respData[1];
			connectionClosingTimeout = respData[2];
			protocols = respData[3].toString().split(",");
			
			timer = new Timer( Math.ceil(heartBeatTimeout*.75)*1000);
			timer.addEventListener(TimerEvent.TIMER, onHeartBeatTimer);
			//timer.start();
			
			var flashSupported:Boolean = false;
			for ( var i:int=0; i<protocols.length; i++ ){
				if ( protocols[i] == "flashsocket" ){
					flashSupported = true;
					break;
				}
			}
			this.socketURL = this.socketURL + "/" + sessionID;
			
			
			onHandshake(event);
			
		}
		protected function onHandshake(event:Event):void{
			MonsterDebugger.trace(this, "onHandshake: "+event.type);
			
			loadDefaultPolicyFile(socketURL);
			webSocket = new WebSocket(this, socketURL, protocol, proxyHost, proxyPort, headers);
			webSocket.addEventListener("event", onData);
			webSocket.addEventListener(Event.CLOSE, onClose);
			webSocket.addEventListener(Event.CONNECT, onConnect);
			webSocket.addEventListener(IOErrorEvent.IO_ERROR, onIoError);
			webSocket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);
		}
		protected function onHeartBeatTimer(event:TimerEvent):void{
			this._onHeartbeat();
		}
		
		protected function onDiscoverError(event:Event):void{
			MonsterDebugger.trace(this, "onDiscoverError: "+event.type);
			if ( event is HTTPStatusEvent ){
				MonsterDebugger.trace(this, "onDiscoverError status: "+(event as HTTPStatusEvent).status);
				if ( (event as HTTPStatusEvent).status != 200){
					//we were unsuccessful in connecting to server for discovery
					var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CONNECT_ERROR);
					dispatchEvent(fe);
				}
			}
		}
		protected function onHandshakeError(event:Event):void{
			MonsterDebugger.trace(this, "onHandshakeError: "+event.type);
			if ( event is HTTPStatusEvent ){
				if ( (event as HTTPStatusEvent).status != 200){
					//we were unsuccessful in connecting to server for discovery
					var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CONNECT_ERROR);
					dispatchEvent(fe);
				}
			}
		}
		
		protected function onClose(event:Event):void{
			MonsterDebugger.trace(this, "onClose" +  this.channel);
			var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CLOSE);
			dispatchEvent(fe);
		}
		
		protected function onConnect(event:Event):void{
			MonsterDebugger.trace(this, "onConnect" +  this.channel);
			var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CONNECT);
			dispatchEvent(fe);
		}
		protected function onIoError(event:Event):void{
			MonsterDebugger.trace(this, "onIoError");
			var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.IO_ERROR);
			dispatchEvent(fe);
		}
		protected function onSecurityError(event:Event):void{
			MonsterDebugger.trace(this, "onSecurityError");
			var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.SECURITY_ERROR);
			dispatchEvent(fe);
		}
		
		protected function loadDefaultPolicyFile(wsUrl:String):void {
			var URLUtil:URL = new URL(wsUrl);
			var policyUrl:String = "xmlsocket://" + URLUtil.hostname + ":843";
			log("policy file: " + policyUrl);
			
			Security.loadPolicyFile(policyUrl);
		}
		
		public function getOrigin():String {
			var URLUtil:URL = new URL(this.callerUrl);
			return (URLUtil.protocol + "://" + URLUtil.host.toLowerCase());
		}
		
		public function getCallerHost():String {
			return null;
			//I dont think we need this
			//return URLUtil.getServerName(this.callerUrl);
		}
		public function log(message:String):void {
			MonsterDebugger.trace(this, "log: " +  message);
			if (debug) {
				trace("webSocketLog: " + message);
			}
		}
		
		public function error(message:String):void {
			MonsterDebugger.trace(this, "error: " +  message);
			trace("webSocketError: "  + message);
		}
		
		public function fatal(message:String):void {
			MonsterDebugger.trace(this, "fatal: " +  message);
			trace("webSocketError: " + message);
		}
		
		/////////////////////////////////////////////////////////////////
		/////////////////////////////////////////////////////////////////
		protected var frame:String = '~m~';
		
		protected function onData(e:*):void{
			var event:Object = (e.target as WebSocket).receiveEvents();
			var data:Object = event[0];
			
			if ( data.type == "message" ){
				this._setTimeout();
				var msg:String = decodeURIComponent(data.data);
				if (msg){
					this._onMessage(msg);
				}
			}else if ( data.type == "open") {
				//this is good I think
			}else if ( data.type == "close" ){
				var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CLOSE);
				dispatchEvent(fe);
			}else{
				
				log("We got a data message that is not 'message': " + data.type);
			}
		}
		private function _setTimeout():void{
			
		}
		
		public var connected:Boolean;
		public var connecting:Boolean;
		
		private function _onMessage(message:String):void{
			trace("_onMessage", message);
			//https://github.com/LearnBoost/socket.io-spec#Encoding
			/*	0		Disconnect
				1::	Connect
				2::	Heartbeat
				3:: Message
				4:: Json Message
				5:: Event
				6	Ack
				7	Error
				8	noop
			*/
			var dm:Object = deFrame(message);
			
			switch ( dm.type ){
				case '0':
					this._onDisconnect();
					break;
				case '1':
					//check which channel we are on
					if(dm.endpoint == this.channel){
						this._onConnect();
					}else{
						trace("Connecting to: "+'1::'+this.channel);
						//connect to the endpoint
						try{
							webSocket.send('1::'+this.channel);
						}catch(err:Error){
						
						}
					}
					break;
				case '2':
					this._onHeartbeat();
					break;
				case '3':
					var fem:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.MESSAGE);
					fem.data = dm.msg;
					dispatchEvent(fem);
					break;
				case '4':
					var fe:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.MESSAGE);
					fe.data = com.adobe.serialization.json.JSON.decode(dm.msg);
					dispatchEvent(fe);
					break;
				case '5':
					var m:Object = com.adobe.serialization.json.JSON.decode(dm.msg);
					var e:FlashSocketEvent = new FlashSocketEvent(m.name);
					e.data = m.args;
					dispatchEvent(e);
					break;
				case '6':
					var parts:Object =  this.ackRegexp.exec(dm.msg);
					var id:int = int(parts[1]);
					var args:Array = com.adobe.serialization.json.JSON.decode(parts[2]);
					if (this.acks.hasOwnProperty(id)) {
						var func:Function = this.acks[id] as Function;
						//pass however many args the function is looking for back to it
						if (args.length >  func.length) {
							func.apply(null, args.slice(0, func.length));
						} else {
							func.apply(null,args);
						}
						
						delete  this.acks[id];
					}
					break;
					
			}
			
		}
		protected function deFrame(message:String):Object{
			var arrMsg:Array = message is String ? message.split(":") : [];
			
			var type:String = arrMsg.length > 0 ? arrMsg[0] : "";
			var id:String = arrMsg.length > 1 ? arrMsg[1] : null;
			var endpoint:String = arrMsg.length > 2 ? arrMsg[2] : "";
			//this later portion won't work - the message could contain ':' - need to pull remaining array and rejoin
			var msg:String = arrMsg.length > 3 ? arrMsg.slice(3).join(":") : null;
			
			return {type: type, msg: msg, id:id, endpoint:endpoint};
		}
		private function _decode(data:String):Array{
			var messages:Array = [], number:*, n:*;
			do {
				if (data.substr(0, 3) !== frame) return messages;
				data = data.substr(3);
				number = '', n = '';
				for (var i:int = 0, l:int = data.length; i < l; i++){
					n = Number(data.substr(i, 1));
					if (data.substr(i, 1) == n){
						number += n;
					} else {	
						data = unescape(data.substr(number.length + frame.length));
						number = Number(number);
						break;
					} 
				}
				messages.push(data.substr(0, number)); // here
				data = data.substr(number);
			} while(data !== '');
			return messages;
		}
		
		private function _onHeartbeat():void{
			try{
				webSocket.send( '2::' ); // echo
			}catch(err:Error){
			
			}
		};
		
		public function send(msg:Object, event:String = null,callback:Function = null):void{
			try{
				var messageId: String = "";
				
				if (null != callback) {
					//%2B is urlencode(+)
					messageId = this.ackId.toString() + '%2B';
					this.acks[this.ackId] = callback;
					this.ackId++;
				}
				
				if ( event == null ){
					if ( msg is String){
						//webSocket.send(_encode(msg));
						webSocket.send('3:'+messageId+':'+this.channel+':' + msg as String);
					}else if ( msg is Object ){
						webSocket.send('4:'+messageId+':'+this.channel+':' + com.adobe.serialization.json.JSON.encode(msg));
					}else{
						throw("Unsupported Message Type");
					}
				}else{
					webSocket.send('5:'+messageId+':'+this.channel+':' + com.adobe.serialization.json.JSON.encode({"name":event,"args":msg}));
				}
			}catch(err:Error){
				trace("Unable to send message");
			}
		}
		
		public function emit(event:String, msg:Object,  callback:Function = null):void{
			send(msg, event, callback) 
		}
		
		private function _onConnect():void{
			this.connected = true;
			this.connecting = false;
			//if we're on a specific channel then we need to tell the server to switch us over
			
			var e:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.CONNECT);
			dispatchEvent(e);
		};
		private function _onDisconnect():void{
			this.connected = false;
			this.connecting = false;
			var e:FlashSocketEvent = new FlashSocketEvent(FlashSocketEvent.DISCONNECT);
			dispatchEvent(e);
		};
		
		private function _encode(messages:*, json:Boolean=false):String{
			var ret:String = '',
				message:String,
				messages:* =  (messages is Array) ? messages : [messages];
			for (var i:int = 0, l:int = messages.length; i < l; i++){
				message = messages[i] === null || messages[i] === undefined ? '' : (messages[i].toString());
				if ( json ) {
					message = "~j~" + message;
				}
				ret += frame + message.length + frame + message;
			}
			return ret;
		};
	}
}