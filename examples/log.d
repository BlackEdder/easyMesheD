import easymeshed : EasyMesh;

void main(string[] args)
{
    import std.conv : to;
    import std.stdio : writeln;
    import core.thread : Thread;
    import std.datetime : dur;

    if (args.length == 3) {
        auto mesh = new EasyMesh(args[1], args[2].to!int);

        mesh.setReceiveCallback((from, msg) {
            writeln("Received: ", msg);
        });
        while(true) {
            mesh.update();
            Thread.sleep( dur!("msecs")(500) );
            //mesh.sendBroadcast("bla");
        }
    } else
        "Need to pass gateway and port to use".writeln;
}
