extends Node

var tests_ok := 0
var tests_names := []

func _ready():
	_run_utils_tests()
	print(str(tests_ok) + " test(s) run and passed.")	
	
	if tests_names.size() > 0:
		print("Successful named tests:")
		for name in tests_names:
			print("- " + name)

func _run_utils_tests():
	var url = "https://url"
	var result = PhoenixUtils.add_url_params(url)
	test(url == result)
	
	result = PhoenixUtils.add_url_params(url + "/", {foo = true})
	test(result == url + "/?foo=True")
	
	result = PhoenixUtils.add_url_params(url + "/?param=random&", {foo = true})
	test(result == url + "/?param=random&foo=True")
	
	result = PhoenixUtils.add_url_params(url, {foo = true})
	test(result == url + "?foo=True")
	
	result = PhoenixUtils.add_url_params(result, {bar = "baz", "number": 12.5})
	test(result == url + "?foo=True&bar=baz&number=12.5")

func test(condition : bool, name = null):
	assert(condition)
	tests_ok += 1
	if name: tests_names.append(name)