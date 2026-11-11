import type { PoolClient, QueryResultRow } from "pg";
import { getPool, withTransaction } from "./pool";
export const query = <T extends QueryResultRow = QueryResultRow>(sql: string, values: any[] = []) => getPool().query<T>(sql, values);
export async function withClient<T>(fn: (client: PoolClient) => Promise<T>) { return withTransaction(fn); }
