import easymeshed : EasyMesh;

void main(string[] args)
{
    import std.conv : to;
    import std.stdio : writeln;
    if (args.length == 3)
        auto mesh = new EasyMesh(args[1], args[2].to!int);
    else
        "Need to pass gateway and port to use".writeln;
}
