package tools;
import haxe.rtti.Type;

class Proxy extends haxe.remoting.Proxy<handler.RemotingApi> {
}

class ApiSync {

	static var FILES = [
		{ file : "flash.xml", platform : "flash" },
		{ file : "neko.xml", platform : "neko" },
		{ file : "js.xml", platform : "js" },
	];

	var api : Proxy;
	var current : StringBuf;
	var typeParams : Array<String>;
	var curPackage : String;
	var previousContent : String;
	var id : Int;

	function new(api) {
		this.api = api;
		id = 0;
	}

	function print(str) {
		current.add(str);
	}

	function keyword(str) {
		current.add("[kwd]"+str+"[/kwd] ");
	}

	function prefix( arr : Array<String>, path : String ) {
		var arr = arr.copy();
		for( i in 0...arr.length )
			arr[i] = path + "." + arr[i];
		return arr;
	}

	function formatPath( path : String ) {
		if( path.substr(0,7) == "flash9." )
			return "flash."+path.substr(7);
		var pack = path.split(".");
		if( pack.length > 1 && pack[pack.length-2].charAt(0) == "_" ) {
			pack.splice(-2,1);
			path = pack.join(".");
		}
		return path;
	}

	function makeRights(r) {
		return switch(r) {
		case RNormal: "default";
		case RNo: "null";
		case RMethod(m): m;
		case RDynamic: "dynamic";
		case RF9Dynamic: "f9dynamic";
		}
	}

	function processPath( path : Path, ?params : List<Type> ) {
		print(makePath(path));
		if( params != null && !params.isEmpty() ) {
			print("<");
			for( t in params )
				processType(t);
			print(">");
		}
	}

	function display<T>( l : List<T>, f : T -> Void, sep : String ) {
		var first = true;
		for( x in l ) {
			if( first )
				first = false;
			else
				print(sep);
			f(x);
		}
	}

	function processType( t : Type ) {
		switch( t ) {
		case TUnknown:
			print("Unknown");
		case TEnum(path,params):
			processPath(path,params);
		case TClass(path,params):
			processPath(path,params);
		case TTypedef(path,params):
			processPath(path,params);
		case TFunction(args,ret):
			if( args.isEmpty() ) {
				processPath("Void");
				print(" -> ");
			}
			for( a in args ) {
				if( a.opt )
					print("?");
				if( a.name != null && a.name != "" )
					print(a.name+" : ");
				processTypeFun(a.t,true);
				print(" -> ");
			}
			processTypeFun(ret,false);
		case TAnonymous(fields):
			print("{ ");
			var me = this;
			display(fields,function(f) {
				me.print(f.name+" : ");
				me.processType(f.t);
			},", ");
			print("}");
		case TDynamic(t):
			if( t == null )
				processPath("Dynamic");
			else {
				var l = new List();
				l.add(t);
				processPath("Dynamic",l);
			}
		}
	}

	function processTypeFun( t : Type, isArg ) {
		var parent =  switch( t ) { case TFunction(_,_): true; case TEnum(n,_): isArg && n == "Void"; default : false; };
		if( parent )
			print("(");
		processType(t);
		if( parent )
			print(")");
	}


	function makeLink( path, ?title ) {
		return "[[/api/"+path.split(".").join("/")+ if( title == null ) "]]" else "|"+title+"]]";
	}

	function makePath( path ) {
		for( x in typeParams )
			if( x == path )
				return path.split(".").pop();
		return makeLink(path);
	}

	function processIndex( buf : StringBuf, t : TypeTree, depth : String ) {
		switch( t ) {
		case TPackage(name,full,subs):
			var isPrivate = name.charAt(0) == "_";
			if( isPrivate || name == "Remoting" ) return;
			var uid = "pack"+(id++);
			buf.add(depth+"[$clic:"+uid+"][pack]"+name+"[/pack][/$clic:"+uid+"] \n");
			depth = "  "+depth;
			buf.add(depth+"[$id:"+uid+"]\n");
			for( x in subs )
				processIndex(buf,x,depth);
			buf.add(depth+"[/$id:"+uid+"]\n");
		default:
			var i = TypeApi.typeInfos(t);
			if( i.isPrivate || i.path == "@Main" || StringTools.endsWith(i.path,"__") )
				return;
			buf.add(depth+makeLink(i.path)+"\n");
		}
	}

	function process( t : TypeTree, lang : String ) {
		switch( t ) {
		case TPackage(_,full,subs):
			var old = curPackage;
			curPackage = full;
			for( x in subs )
				process(x,lang);
			curPackage = old;
		default:
			var i = TypeApi.typeInfos(t);
			var path = i.path.split(".");
			var name = path[path.length-1];
			path.unshift("api");
			// get previous content
			var prev = api.read(path,lang);
			previousContent = (prev == null) ? "" : prev.content;
			// set context
			typeParams = prefix(i.params,i.path);
			current = new StringBuf();
			// build
			print("[api]\n\n");
			switch(t) {
			case TPackage(_,_,_):
				throw "assert";
			case TClassdecl(c):
				processClass(c);
			case TEnumdecl(e):
				processEnum(e);
			case TTypedecl(t):
				processTypedef(t);
			}
			print("[/api]");
			// save
			if( api.write(path,lang,name,current.toString()) )
				neko.Lib.println("Updating "+i.path+" ["+lang+"]");
			else
				neko.Lib.print("Skipping "+i.path+" ["+lang+"]\t\t\r");
		}
	}

	function processInfos( t : TypeInfos ) {
		if( t.module != null )
			print('[mod]import '+t.module+'[/mod]\n');
		if( !t.platforms.isEmpty() ) {
			print('[pf]Available in ');
			display(t.platforms,print,", ");
			print('[/pf]\n');
		}
		processDoc(t.doc,"");
		print("\n");
	}

	function processClass( c : Classdef ) {
		// name
		print("[name]");
		if( c.isExtern )
			keyword("extern");
		if( c.isPrivate )
			keyword("private");
		if( c.isInterface )
			keyword("interface");
		else
			keyword("class");
		print(formatPath(c.path));
		if( c.params.length != 0 ) {
			print("<");
			print(c.params.join(", "));
			print(">");
		}
		print("[/name]\n");
		// inheritance
		if( c.superClass != null ) {
			print("[oop]extends ");
			processPath(c.superClass.path,c.superClass.params);
			print("[/oop]\n");
		}
		for( i in c.interfaces ) {
			print("[oop]implements ");
			processPath(i.path,i.params);
			print("[/oop]\n");
		}
		if( c.dynamic != null ) {
			var d = new List();
			d.add(c.dynamic);
			print("[oop]implements ");
			processPath("Dynamic",d);
			print("[/oop]\n");
		}
		// datas
		processInfos(c);
		// fields
		for( f in c.fields )
			processClassField(c.platforms,f,false);
		for( f in c.statics )
			processClassField(c.platforms,f,true);
	}

	function processClassField(platforms : Platforms,f : ClassField,stat) {
		if( !f.isPublic )
			return;
		var oldParams = typeParams;
		if( f.params != null )
			typeParams = typeParams.concat(prefix(f.params,f.name));
		print('[field]');
		if( stat ) keyword("static");
		var isMethod = false;
		switch( f.type ) {
		case TFunction(args,ret):
			if( f.get == RNormal && (f.set == RNormal || f.set == RF9Dynamic) ) {
				isMethod = true;
				if( f.set == RF9Dynamic )
					keyword("f9dynamic");
				keyword("function");
				print(f.name);
				if( f.params != null )
					print("<"+f.params.join(", ")+">");
				var space = args.isEmpty() ? "" : " ";
				print("("+space);
				var me = this;
				display(args,function(a) {
					if( a.opt )
						me.print("?");
					if( a.name != null && a.name != "" ) {
						me.print(a.name);
						me.print(" : ");
					}
					me.processType(a.t);
				},", ");
				print(space+") : ");
				processType(ret);
			}
		default:
		}
		if( !isMethod ) {
			keyword("var");
			print(f.name);
			if( f.get != RNormal || f.set != RNormal )
				print("("+makeRights(f.get)+","+makeRights(f.set)+")");
			print(" : ");
			processType(f.type);
		}
		if( f.platforms.length != platforms.length ) {
			print('[pf]Available in ');
			display(f.platforms,print,", ");
			print('[/pf]');
		}

		print("\n");
		var tag = stat ? " s_" + f.name : " _" + f.name;
		processDoc(f.doc,tag);
		print('[/field]\n\n');
		if( f.params != null )
			typeParams = oldParams;
	}


	function processEnum(e : Enumdef) {
		print("[name]");
		if( e.isExtern )
			keyword("extern");
		if( e.isPrivate )
			keyword("private");
		keyword("enum");
		print(formatPath(e.path));
		if( e.params.length != 0 ) {
			print("<");
			print(e.params.join(", "));
			print(">");
		}
		print('[/name]\n');
		processInfos(e);
		// constructors
		for( c in e.constructors ) {
			print('[construct]\n');
			print(c.name);
			if( c.args != null ) {
				print("(");
				var me = this;
				display(c.args,function(a) {
					if( a.opt )
						me.print("?");
					me.print(a.name);
					me.print(" : ");
					me.processType(a.t);
				},",");
				print(")");
			}
			print("\n");
			processDoc(c.doc," _"+c.name);
			print("[/construct]\n\n");
		}
	}

	function processTypedef(t : Typedef) {
		print('[name]');
		if( t.isPrivate )
			keyword("private");
		keyword("typedef");
		print(formatPath(t.path));
		if( t.params.length != 0 ) {
			print("&lt;");
			print(t.params.join(", "));
			print("&gt;");
		}
		print('[/name]\n');
		processInfos(t);
		if( t.platforms.length == 0 ) {
			processTypedefType(t.type,t.platforms,t.platforms);
			return;
		}
		var platforms = new List();
		for( p in t.platforms )
			platforms.add(p);
		for( p in t.types.keys() ) {
			var td = t.types.get(p);
			var support = new List();
			for( p2 in platforms )
				if( TypeApi.typeEq(td,t.types.get(p2)) ) {
					platforms.remove(p2);
					support.add(p2);
				}
			if( support.length == 0 )
				continue;
			processTypedefType(td,t.platforms,support);
		}
	}

	function processTypedefType(t,all,platforms) {
		switch( t ) {
		case TAnonymous(fields):
			print('[anon]\n\n');
			for( f in fields ) {
				processClassField(all,{
					name : f.name,
					type : f.t,
					isPublic : true,
					doc : null,
					get : RNormal,
					set : RNormal,
					params : null,
					platforms : platforms,
				},false);
			}
			print('[/anon]\n');
		default:
			if( all.length != platforms.length ) {
				print('[pf]Defined in ');
				display(platforms,print,", ");
				print('[/pf]\n');
			}
			print('[tdef]= ');
			processType(t);
			print('[/tdef]\n');
		}
		print("\n");
	}

	function processDoc( doc : String, tag : String ) {
		print('[doc'+tag+']');
		var r = "\\[doc"+tag+"\\]([^\\0]*?)\\[/doc"+tag+"\\]";
		var rdoc = new EReg(r,"");
		if( rdoc.match(previousContent) && StringTools.trim(doc = rdoc.matched(1)) != ""  )
			print(doc);
		else if( doc == null || StringTools.trim(doc) == "" )
			print("\n");
		else {
			// unixify line endings
			doc = doc.split("\r\n").join("\n").split("\r").join("\n");
			// trim stars
			doc = ~/^([ \t]*)\*+/gm.replace(doc, "$1");
			doc = ~/\**[ \t]*$/gm.replace(doc, "");
			// remove single line returns
			doc = ~/\n[\t ]*([^\n])/g.replace(doc," $1");
			// change double lines into single ones
			doc = ~/\n[\t ]*\n/g.replace(doc,"\n");
			// code style
			doc = ~/[\[\]]/g.replace(doc,"''");
			// trim
			doc = StringTools.trim(doc);
			// print
			print("\n");
			print(doc);
			print("\n");
		}
		print('[/doc'+tag+']\n');
	}

	static function input( name, def ) {
		if( def != null )
			return def;
		neko.Lib.print(name+": ");
		return neko.io.File.stdin().readLine();
	}

	static function log( msg ) {
		neko.Lib.println(msg+"...");
	}

	public static function main() {
		var args = neko.Sys.args();
		var host = input("Host",args[0]).split(":");
		var config = {
			host : host[0],
			port : if( host.length > 1 ) Std.parseInt(host[1]) else 80,
			user : input("User",args[1]),
			pass : input("Pass",args[2]),
		};
		var url = "http://"+config.host+":"+config.port+"/wiki/remoting";
		var cnx = haxe.remoting.Connection.urlConnect(url);
		var api = new Proxy(cnx.api);
		if( config.user != null ) {
			var inf = api.login(config.user,config.pass);
			cnx = haxe.remoting.Connection.urlConnect(url+"?sid="+inf.sid);
			api = new Proxy(cnx.api);
		}
		var s = new ApiSync(api);
		log("Reading files");
		var parser = new haxe.rtti.XmlParser();
		for( f in FILES ) {
			var data = neko.io.File.getContent(f.file);
			var x = Xml.parse(data).firstElement();
			parser.process(x,f.platform);
		}
		parser.sort();
		log("Building index");
		var buf = new StringBuf();
		buf.add("[api_index]\n\n");
		for( x in parser.root )
			s.processIndex(buf,x,"  * ");
		buf.add("\n[/api_index]");
		log("Writing index");
		var index = buf.toString();
		var langs = api.getLangs(["api"]);
		for( l in langs )
			api.write(["api"],l,"haXe API",index);
		for( l in langs )
			for( x in parser.root )
				s.process(x,l);
		log("\nDone");
	}

}