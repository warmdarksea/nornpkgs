from py_hello import main


def test_prints_hello_world(capsys):
    main()
    assert capsys.readouterr().out == "hello, world!\n"
