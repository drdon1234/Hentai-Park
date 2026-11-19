type Draft = { data: Record<string, unknown>; portrait?: string };
let database: Promise<IDBDatabase> | undefined;
function openDrafts() {
  if (!database)
    database = new Promise<IDBDatabase>((resolve, reject) => {
      const req = indexedDB.open('hp-tavern-editor', 1);
      req.onupgradeneeded = () => req.result.createObjectStore('drafts');
      req.onerror = () => {
        database = undefined;
        reject(req.error);
      };
      req.onsuccess = () => resolve(req.result);
    });
  return database;
}
export async function readDraft(key: string): Promise<Draft | undefined> {
  const db = await openDrafts();
  return new Promise((resolve, reject) => {
    const req = db.transaction('drafts').objectStore('drafts').get(key);
    req.onsuccess = () => resolve(req.result as Draft | undefined);
    req.onerror = () => reject(req.error);
  });
}
export async function writeDraft(key: string, draft?: Draft) {
  const db = await openDrafts();
  return new Promise<void>((resolve, reject) => {
    const txn = db.transaction('drafts', 'readwrite'),
      store = txn.objectStore('drafts');
    if (draft) store.put(draft, key);
    else store.delete(key);
    txn.oncomplete = () => resolve();
    txn.onabort = () => reject(txn.error);
    txn.onerror = () => reject(txn.error);
  });
}
