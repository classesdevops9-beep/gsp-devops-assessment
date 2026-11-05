/**
 * MongoDB Least-Privilege Application User Initialization Script
 * Runs once upon initial container bootstrap.
 */

const targetDb = 'conduit';
const appUser = 'conduit_user';
const appPassword = 'conduit_secure_password';

print(`[INIT-MONGO] Creating least-privilege user '${appUser}' on database '${targetDb}'...`);

const dbInstance = db.getSiblingDB(targetDb);

dbInstance.createUser({
  user: appUser,
  pwd: appPassword,
  roles: [
    {
      role: 'readWrite',
      db: targetDb
    }
  ]
});

print(`[INIT-MONGO] Least-privilege user '${appUser}' created with [readWrite] role strictly on '${targetDb}'.`);
