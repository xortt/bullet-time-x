/**
    Inventory class that stores the reference to the BulletTime handler.
    This is one is only used when a player that is loading a saved game that did not have the BulletTime handler initialized,
    saves that game with the static event handler initialized.
    This will keep track of all the data that was stored in the Bullet Time handler created by the static handler.
*/
class BtHandlerRef : Inventory
{
    BulletTime btHandler;
}

/**
    This class purpose is only to be used when the user loads a saved game that did not have the BulletTime handler initialized.
    It will 'create' a BulletTime handler and simulate it.
    This is a workaround to avoid the user to have to restart the game (a new game) to have BulletTime working.
*/
class BulletTimeStatic : StaticEventHandler
{
    BulletTime btHandler;
    bool btEventHandlerInitialized;
    bool btHandlerRemoved;

    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "bt_handler_remove" && !btEventHandlerInitialized && btHandler)
        {
            btHandler.removeHandler(true);
            btHandler = null;
        }

        if (e.Name == "bt_handler_reload" && !btEventHandlerInitialized)
        {
            btHandlerRemoved = false;
            if (!btHandler) manuallyInitHandler();

            btHandler.reloadHandler();
        }

        if (btEventHandlerInitialized || btHandlerRemoved) return;
        if (btHandler) btHandler.NetworkProcess(e);
    }

    void manuallyInitHandler()
    {
        if (!btHandler && !btEventHandlerInitialized)
        {
            BulletTime handler = new ("BulletTime");
            btHandler = handler;
            btHandler.createdFromEventStaticHandler = true;

            PlayerInfo p = players[consoleplayer];
            if (p && p.mo)
            {
                p.mo.GiveInventory("BtHandlerRef", 1);
                Inventory inv = p.mo.FindInventory("BtHandlerRef");
                if (inv)
                {
                    BtHandlerRef btHandlerRef = BtHandlerRef(inv);
                    btHandlerRef.btHandler = btHandler;
                }
            }

            btHandler.WorldLoaded(null);
        }
    }

    void manuallyLoadHandlerFromSave()
    {
        if (!btHandler && !btEventHandlerInitialized)
        {
            PlayerInfo p = players[consoleplayer];
            if (p && p.mo)
            {
                Inventory inv = p.mo.FindInventory("BtHandlerRef");
                if (inv)
                {
                    BtHandlerRef btHandlerRef = BtHandlerRef(inv);
                    btHandler = btHandlerRef.btHandler;
                }
                else
                {
                    manuallyInitHandler();
                }
            }
        }
    }

    override void WorldTick()
    {
        if (btEventHandlerInitialized || btHandlerRemoved) return;
        if (!btEventHandlerInitialized && !btHandler) 
        {
            manuallyLoadHandlerFromSave();
        }

        if (btHandler) btHandler.WorldTick();
    }

    override void WorldLoaded(WorldEvent e)
	{
        if (e.IsSaveGame)
        { // when a saved game is loaded, there is a chance that it doesnt have bullet time handler so it must be initialized
            btEventHandlerInitialized = false;
            btHandler = null;
        }
        if (btEventHandlerInitialized || btHandlerRemoved) return;
        if (btHandler) btHandler.WorldLoaded(e);
    }

    override void WorldUnloaded(WorldEvent e)
    {
        if (e.IsSaveGame)
        {
            btEventHandlerInitialized = false;
            btHandler = null;
        }

        if (btEventHandlerInitialized || btHandlerRemoved) return;
        if (btHandler) btHandler.WorldUnloaded(e);
    }

    override void RenderOverlay(RenderEvent e)
    {
        if (btEventHandlerInitialized || btHandlerRemoved) return;

        if (btHandler) btHandler.RenderOverlay(e);
    }
}