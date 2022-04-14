class BtSectorInfo : Object
{
	bool hasStopped;
	double ceilingPos;
	double ceilingSpeed;
	double floorPos;
	double floorSpeed;
	double postCeilingPos;
	double postFloorPos;
	int sectorID;
	int tics;
	Thinker thinkerRef;

	static BtSectorInfo initialize(Sector sec, Thinker thinkerSector)
	{
		BtSectorInfo sectorInfo = new("BtSectorInfo");

		sectorInfo.sectorID = sec.sectornum;
		sectorInfo.floorPos = sec.floorplane.D;
		sectorInfo.ceilingPos = sec.ceilingplane.D;
		sectorInfo.floorSpeed = 0;
		sectorInfo.ceilingSpeed = 0;
		sectorInfo.postFloorPos = 0;
		sectorInfo.postCeilingPos = 0;
		sectorInfo.tics = -2;
		sectorInfo.hasStopped = false;
		sectorInfo.thinkerRef = thinkerSector;

		return sectorInfo;
	}
}