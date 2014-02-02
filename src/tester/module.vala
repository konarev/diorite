/*
 * Copyright 2014 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

namespace Diorite
{

public class TestModule: GLib.TypeModule
{
	[CCode (has_target = false)]
	public delegate void ModuleInitFunc(GLib.TypeModule type_module);
	
	private string name = null;
	private GLib.Module module = null;
	public string? error = null;
	
	public TestModule(string name)
	{
		this.name = name;
	}
	
	public override bool load()
	{
		string? dir = Path.get_dirname(name);
		var file = Path.get_basename(name);
		var module_path = Module.build_path(name == file ? null : dir, file);
		module = Module.open(module_path, GLib.ModuleFlags.BIND_LAZY);
		if (module == null)
		{
			error = "Module %s not found. %s\n".printf(name, Module.error() ?? "");
			return false;
		}
		
		string symbol = "module_init";
		void* func = null;
		if (!module.symbol(symbol, out func))
		{
			error = "Module init symbol %s not found. %s\n".printf(symbol, Module.error() ?? "");
			return false;
		}
		
		((ModuleInitFunc) func)(this);
		return true;
	}
	
	public override void unload()
	{
		module = null;
	}
	
	public TestAdapter? load_test(TestSpec spec)
	{
		var name = spec.name;
		var i = name.last_index_of(".");
		if (i < 1)
		{
			error = "Invalid test name %s.".printf(name);
			return null;
		}
		
		var type_name = name.substring(0, i).replace(".", "");
		var test_name = name.substring(i + 1);
		var type = Type.from_name(type_name);
		if (!type.is_object())
		{
			error = "Invalid type %s.".printf(type_name);
			return null;
		}
		
		var symbol = get_c_func(type_name, test_name);
		message("%s %s %s %s", type_name, test_name, type.name(), symbol);
		var test_case = Object.new(type) as TestCase;
		void* func = null;
		if (!module.symbol(symbol, out func))
		{
			error = "Module symbol %s not found. %s\n".printf(symbol, Module.error() ?? "");
			return null;
		}
		
		if (!spec.async)
			return new Adapter(test_case, name, (TestFunc) func);
		
		symbol += "_finish";
		void* func2 = null;
		if (!module.symbol(symbol, out func2))
		{
			error = "Module symbol %s not found. %s\n".printf(symbol, Module.error() ?? "");
			return null;
		}
		return new AsyncAdapter(test_case, name, (TestFuncBegin) func, (TestFuncEnd) func2);
	}
	
	private string get_c_func(string klass, string method)
	{
		unichar c;
		var buffer = new StringBuilder.sized(klass.length + method.length + 10);
		for (int i = 0; klass.get_next_char(ref i, out c);)
		{
			if (i > 1 && c.isupper())
				buffer.append_c('_').append_unichar(c.tolower());
			else if (c.isupper())
				buffer.append_unichar(c.tolower());
			else
				buffer.append_unichar(c);
		}
		buffer.append_c('_').append(method);
		return buffer.str;
	}
}

} // namespace Diorite
