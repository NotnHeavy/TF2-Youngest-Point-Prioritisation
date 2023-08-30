//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#include <SMTC/SMTCHeader>
#include <SMTC/Vector>
#include <SMTC/CBaseEntity>
#include <SMTC/CUtlVector>
#include <SMTC/Ray_t>
#include <SMTC/CEngineTrace>
#include <SMTC/CGameTrace>
#include <SMTC/tf/flame_point_t>
#include <SMTC/tf/tf_point_t>
#include <SMTC/SMTC>

#define PLUGIN_NAME "NotnHeavy - Youngest Point Prioritisation"

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

static Handle SDKCall_CTFPointManager_ShouldCollide;
static Handle SDKCall_CTFPointManager_GetRadius;
static Handle SDKCall_CTFPointManager_OnCollide;

//////////////////////////////////////////////////////////////////////////////
// PLUGIN INFO                                                              //
//////////////////////////////////////////////////////////////////////////////

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "NotnHeavy",
    description = "Prioritises the youngest flame point instead of the oldest flame point in damage calculations for flamethrowers.",
    version = "1.0",
    url = "none"
};

//////////////////////////////////////////////////////////////////////////////
// INITIALISATION                                                           //
//////////////////////////////////////////////////////////////////////////////

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    // Load config data.
    GameData config = LoadGameConfigFile(PLUGIN_NAME);

    // Set up SDKCalls.
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFPointManager::ShouldCollide()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CBaseEntity* pEntity;
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain); // bool
    SDKCall_CTFPointManager_ShouldCollide = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFPointManager::GetRadius()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // tf_point_t* point;
    PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain); // float
    SDKCall_CTFPointManager_GetRadius = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFPointManager::OnCollide()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // CBaseEntity* pEntity;
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // int i;
    SDKCall_CTFPointManager_OnCollide = EndPrepSDKCall();
    
    delete config;

    PrintToServer("--------------------------------------------------------\n\"%s\" has loaded.\n--------------------------------------------------------", PLUGIN_NAME);
}

public void OnMapStart()
{
    SMTC_Initialize();
}

//////////////////////////////////////////////////////////////////////////////
// FORWARDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "tf_flame_manager"))
        SDKHook(entity, SDKHook_Touch, CTFFlameManager_Touch);
}

//////////////////////////////////////////////////////////////////////////////
// SDKHOOKS                                                                 //
//////////////////////////////////////////////////////////////////////////////

// Pre-call CTFFlameManager::Touch().
// Re-write the CUtlVector iteration code to only consider the youngest flame point.
Action CTFFlameManager_Touch(int entityIndex, int otherIndex)
{
    // Get the entity indexes as entities.
    CBaseEntity entity = CBaseEntity.FromIndex(entityIndex);
    CBaseEntity other = CBaseEntity.FromIndex(otherIndex);

    // Get the manager's m_Points CUtlVector, so that we can iterate through the points.
    CUtlVector m_Points = view_as<any>(entity) + SMTC_CTFPointManager_m_Points;

    // Iterate if the entities should be colliding and m_Points isn't empty.
    int size = m_Points.Count();
    if (SDKCall(SDKCall_CTFPointManager_ShouldCollide, entity, other) && size > 0)
    {
        for (int i = size - 1; i >= 0; --i)
        {
            // Get the tf_point_t pointer.
            TF_Point_t point = m_Points.Get(i).Dereference();
            float radius = SDKCall(SDKCall_CTFPointManager_GetRadius, entity, point);
            int flags = 0x4200400B;
            
            // Make the necessary vectors.
            Vector vecMins = STACK_GETRETURN(Vector.StackAlloc(-radius, -radius, -radius));
            Vector vecMaxs = STACK_GETRETURN(Vector.StackAlloc(radius, radius, radius));

            // Set up a ray.
            Ray_t ray = STACK_GETRETURN(Ray_t.StackAlloc());
            ray.InitHull(point.m_vecEndPos, point.m_vecStartPos, vecMins, vecMaxs);

            // Set up a trace and call collision code if the point has hit.
            CGameTrace trace = STACK_GETRETURN(CGameTrace.StackAlloc());
            enginetrace.ClipRayToEntity(ray, flags, other, trace);
            if (trace.DidHit())
            {
                SDKCall(SDKCall_CTFPointManager_OnCollide, entity, other, i);
                break;
            }
        }
    }

    // We handled the call ourselves, so halt further execution.
    return Plugin_Handled;
}