class BtActorInfo : Object
{
	bool isFloorMoving;
	bool nextTicDelete;
    bool playerJumped; // should reset to 0 when pos.z == floorz
	double externalForce;
    double lastSpeed; // last speed, with applied slowdown
    double newChangedSpeed; // new speed with no slowdown
	int id;
	int lastTics;
	int lastWeaponTics[201];
	int lastHealth;
    int powerUpCount;
	int playerJumpTic; // the 2nd tic player jumps, the 1st one Z velocity is applied, 0 is no jumping
    int playerJumpHoldTic; // the tic player is holding jump key
	Actor actorRef;
    PlayerPawn playerRef;
	Sector lastSector;
	State lastState;
	State lastWeaponState[201];
	Vector3 lastVel;
	Vector3 lastOgVel;
    float lastAccelXY;

    static BtActorInfo initialize()
    {
        BtActorInfo actorInfo = new("BtActorInfo");

        actorInfo.lastVel = (0, 0, 0);
        actorInfo.externalForce = 0.0;
        actorInfo.id = 0;
        actorInfo.actorRef = null;
        actorInfo.lastTics = 0;
        actorInfo.lastSpeed = 0.0;
        actorInfo.newChangedSpeed = 0.0;
        actorInfo.lastState = null;
        actorInfo.nextTicDelete = false;
        actorInfo.isFloorMoving = false;
        actorInfo.playerJumpTic = 0;
        actorInfo.playerRef = null;
        actorInfo.lastAccelXY = 0.0;

        return actorInfo;
    }
}