import easymeshed : easyMesh;

void main(string[] args)
{
    import std.conv : to;
    import std.stdio : writeln;
    args.writeln;
    if (args.length == 3)
        auto mesh = easyMesh(args[1], args[2].to!int);
    else
        "Need to pass gateway and port to use".writeln;
}
