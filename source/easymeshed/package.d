module easymeshed;

version (assert) {
    import std.stdio : writeln;
}

string readJsonObject(T)(ref T connection)
{
    import vibe.stream.operations : readUntil;
    import std.range : walkLength;
    import std.algorithm : balancedParens, filter;
    int countOpen = 0;
    bool firstRun = true;
    string line;
    while(countOpen > 0 || firstRun)
    {
        auto segment = cast(string) connection.readUntil([125]);
        auto newOpen = segment.filter!((a) => a == '{').walkLength;
        countOpen += newOpen;
        line ~= segment ~ "}";
        --countOpen;
        firstRun = false;
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
        ubyte[] msgs = [123, 34, 100, 101, 115, 116, 34, 58, 48, 44, 34, 102, 114, 111, 109, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 116, 121, 112, 101, 34, 58, 53, 44, 34, 115, 117, 98, 115, 34, 58, 91, 93, 125, 123, 34, 100, 101, 115, 116, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 102, 114, 111, 109, 34, 58, 49, 51, 54, 49, 48, 52, 56, 56, 44, 34, 116, 121, 112, 101, 34, 58, 52, 44, 34, 109, 115, 103, 34, 58, 123, 34, 116, 105, 109, 101, 34, 58, 49, 56, 48, 56, 56, 53, 50, 56, 55, 44, 34, 110, 117, 109, 34, 58, 48, 44, 34, 97, 100, 111, 112, 116, 34, 58, 102, 97, 108, 115, 101, 125, 125, 
            123, 100, 123, 100, 123, 100, 125, 100, 125, 100, 125].cycle.take(1000).array;

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
    import std.stdio : writeln;
    assert(readJsonObject(m) == q{{d{d{d}d}d}});
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
        connection.keepAlive = true;
        import std.datetime : dur;
        connection.readTimeout = dur!"seconds"(60);
    }

    string readString() 
    {
        assert(connection.connected, "Not connected");
        if (!connection.dataAvailableForRead)
            return "{}";
        return connection.readJsonObject();
    }

    bool connected()
    {
        return connection.connected;
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
        debug writeln("Sending: ", msg);
        assert(connection.connected, "Lost connection when sending");
        //connection.write(msg.map!((a) => a.to!ubyte).array);
        connection.write(msg);
    }

private:
    TCPConnection connection;
}

enum meshPackageType {
    DROP                    = 3,
    TIME_SYNC               = 4,
    NODE_SYNC_REQUEST       = 5,
    NODE_SYNC_REPLY         = 6,
    BROADCAST               = 8,  //application data for everyone
    SINGLE                  = 9   //application data for a single node
};


class EasyMesh 
{
    this(string gateway, int port) 
    {
        import std.random : uniform;
        nodeID = uniform(0, 100000);
        // Setup initial connection
        _gateway = gateway;
        _port = port;
        newConnection(_gateway, _port);
    }

    import std.json : JSONValue;
    private void sendMessage(long destID, JSONValue msg)
    {
        import std.conv : to;
        msg["dest"] = destID;
        msg["from"] = nodeID;

        assert("type" in msg, "All messages need to have a type specified");
        //connections[destID].sendMessage(msg.to!string);

        // TODO currently this just sends it to the only connection available
        auto destination = connections.values[0];
        if (!destination.connected) {
            newConnection(_gateway, _port);
            sendMessage(destID, msg);
        } else {
            destination.sendMessage(msg.to!string);
        }
    }

    void sendSingle(long destID, string msg)
    {
        import std.format : format;
        import std.json : parseJSON;
        sendMessage(destID, 
            format(q{{"type": %d, "msg": "%s"}},
                meshPackageType.SINGLE, msg).parseJSON);

    }

    void sendBroadcast(string msg)
    {
        import std.conv : to;
        import std.format : format;
        
        auto destination = connections.values[0];
        if (!destination.connected) {
            newConnection(_gateway, _port);
            sendBroadcast(msg);
        } else {
            destination.sendMessage(
                format(q{{"from": %s, "type": %d, "msg": "%s"}},
                    nodeID, meshPackageType.BROADCAST, msg));
        }
    }

    void update()
    {
        import std.datetime : dur;
        import std.json : parseJSON;
        foreach(k, v; connections) {
            if (!v.connected)
                newConnection(_gateway, _port);
            else {
                assert(v.connected, "Lost connection");
                if (v.connection.waitForData(dur!("msecs")(10)))
                    handleMessage(v.read());
            }
        }
    }

    void setReceiveCallback(void delegate(long from, JSONValue[string] msg) callBack )
    {
        callBacks ~= callBack;
    }

    private void newConnection(string gateway, int port) 
    {
        import std.conv : to;
        import std.json : parseJSON;
        import std.format : format;
        debug writeln("Setting up connection with: ", _gateway, ":", _port);
        auto connection = EasyMeshConnection(gateway, port);

        connection.connection.waitForData;
        auto json = connection.read();
        auto connectionID = json["from"].integer;
        connections[connectionID] = connection;

        // Say hello
        sendMessage(connectionID, 
            parseJSON(format(q{{"type": %s, "subs":[]}}, 
                meshPackageType.NODE_SYNC_REPLY.to!int)));
        sendMessage(connectionID, 
            parseJSON(format(q{{"type": %s, "subs":[]}}, 
                meshPackageType.NODE_SYNC_REQUEST.to!int)));
    }

    private void handleMessage(JSONValue[string] msg) 
    {
        debug writeln("handleMessage: ", msg);
        auto type = msg["type"].integer;

        if (type == meshPackageType.NODE_SYNC_REQUEST) {
            import std.conv : to;
            import std.json : parseJSON;
            import std.format : format;
            sendMessage(msg["from"].integer, 
                parseJSON(format(q{{"type": %s, "subs":[]}}, 
                    meshPackageType.NODE_SYNC_REPLY.to!int)));
        }
        else if (type == meshPackageType.BROADCAST || type == meshPackageType.SINGLE)
        {
            if (type == meshPackageType.SINGLE && msg["dest"].integer != nodeID)
            {
                debug writeln("Received a message not intended for us: ", msg);
            } else {
                foreach(cb; callBacks) {
                    cb(msg["from"].integer, msg);
                }
            }
        }
    }

private: 
    long nodeID;
    EasyMeshConnection[long] connections;

    alias callBackDelegate = void delegate(long from, JSONValue[string] msg);
    callBackDelegate[] callBacks;

    string _gateway;
    int _port;
}
