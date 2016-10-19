module easymeshed;
import std.stdio : writeln;

string readJsonObject(T)(ref T connection)
{
    import vibe.stream.operations : readUntil;
    import std.range : walkLength;
    import std.algorithm : balancedParens, filter;
    int countOpen = 1;
    string line;
    while(countOpen > 0)
    {
        auto segment = cast(string) connection.readUntil([125]);
        --countOpen;
        auto newOpen = segment.filter!((a) => a == '{').walkLength - 1;
        countOpen += newOpen;
        line ~= segment ~ "}";
    }

    assert(line.balancedParens('{', '}'), "Object not complete");
    return line;
}

unittest 
{
    import std.array : array;
    struct Mock
    {
        import std.range : take, cycle;
        ubyte[] msgs = [123, 34, 100, 101, 115, 116, 34, 58, 48, 44, 34, 102, 114, 111, 109, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 116, 121, 112, 101, 34, 58, 53, 44, 34, 115, 117, 98, 115, 34, 58, 91, 93, 125, 123, 34, 100, 101, 115, 116, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 102, 114, 111, 109, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 116, 121, 112, 101, 34, 58, 52, 44, 34, 109, 115, 103, 34, 58, 123, 34, 116, 105, 109, 101, 34, 58, 49, 56, 48, 56, 56, 53, 50, 56, 55, 44, 34, 110, 117, 109, 34, 58, 48, 44, 34, 97, 100, 111, 112, 116, 34, 58, 102, 97, 108, 115, 101, 125, 125].cycle.take(1000).array;

        auto readUntil(ubyte[] ubs) 
        {
            import std.algorithm : findSplit;
            auto splits = msgs.findSplit(ubs);
            msgs = splits[2];
            return splits[0].array;
        }
    }

    auto m = Mock();

    assert(readJsonObject(m) == q{{"dest":0,"from":13610488,"type":5,"subs":[]}});
    assert(readJsonObject(m) == q{{"dest":13610488,"from":13610488,"type":4,"msg":{"time":180885287,"num":0,"adopt":false}}});
}

/+ 
Start with a minimal implementation that takes a port and starts listening. It will assume you are already connected to a node.

We need to start listening and send an empty array of subconnections. It will also need to implement sync.

We should also make a minimal log example program, which just logs all received messages to the command line
+/
struct EasyMeshConnection
{
    import vibe.data.json;
    import vibe.core.net : TCPConnection;
    this(string gateway, int port) 
    {
        import std.conv : to;
        import vibe.core.net : connectTCP;
        connection = connectTCP(gateway, port.to!(ushort));
        connection.waitForData;
        auto json = read();
        json.writeln;
        connectionID = json["from"].integer;
    }

    string readString() 
    {
        assert(connection.connected, "Not connected");
        if (!connection.dataAvailableForRead)
            return "{}";
        return connection.readJsonObject();
    }

    auto read()
    {
        import std.json : parseJSON;
        auto str = readString();
        return parseJSON(str).object;
    }

    void sendMessage(string msg)
    {
        import std.algorithm : map;
        import std.array : array;
        writeln("Sending: ", msg);
        //connection.write(msg.map!((a) => a.to!ubyte).array);
        connection.write(msg);
    }

private:
    long connectionID;
    TCPConnection connection;
}

class EasyMesh 
{
    this(string gateway, int port) 
    {
        import std.json : parseJSON;
        import std.random : uniform;
        nodeID = uniform(0, 100000);

        import std.algorithm : map;
        import std.conv : to;
        import std.base64;
        import vibe.core.net : connectTCP;

        auto connection = EasyMeshConnection(gateway, port.to!(ushort));
        connections[connection.connectionID] = connection;

        import std.format : format;
        sendMessage(connection.connectionID, 
            parseJSON(q{{"type":6, "subs":[]}}));

        connection.connection.waitForData;
        connection.read().writeln;

        sendMessage(connection.connectionID, 
            parseJSON(q{{"type":5, "subs":[]}}));

        connection.connection.waitForData;
        connection.read().writeln;
        /+
            Further design:
            Add a read (Should return a JSONAA) and send, and sendBroadcast

            Try reading then sending a message with our sub connections ([])

            Read should assert (for now) if it finds two {
        +/
    }

    import std.json : JSONValue;
    void sendMessage(long destID, JSONValue msg)
    {
        import std.conv : to;
        msg["dest"] = destID;
        msg["from"] = nodeID;
        connections[destID].sendMessage(msg.to!string);
    }

private: 
    long nodeID;
    EasyMeshConnection[long] connections;
}
