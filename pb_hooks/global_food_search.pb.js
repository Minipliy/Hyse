/// <reference path="../pb_data/types.d.ts" />

// Bounded server-side search keeps large catalogue pages off the phone. Query
// parameters are bound through PocketBase's filter API and never interpolated.
routerAdd("GET", "/api/hyse/global-foods/search", (c) => {
    const query = String(c.queryParam("q") || "").trim().replace(/\s+/g, " ").slice(0, 80)
    if (query.length < 2) return c.json(200, { items: [] })
    const tokens = query.toLowerCase().replace(/[^a-z0-9äöüßà-ž]+/g, " ").split(" ").filter((value) => value.length >= 2).slice(0, 5)
        .map((value) => value === "mcdonalds" ? "mcdonald" : value === "doener" ? "döner" : value)
    if (!tokens.length) return c.json(200, { items: [] })
    const rankingQuery = query.toLowerCase() === "doener" ? "döner" : query
    try {
        const rows = arrayOf(new DynamicModel({
            id: "", name: "", name_de: "", brand: "", brand_relation: "", barcode: "", unit: "",
            serving_size: -0, calories: -0, carbs: -0, protein: -0, fat: -0, sugar: -0, fiber: -0,
            saturated_fat: -0, salt: -0, moderation_status: "", creator: "", source: "", source_id: "", is_fruit: false
        }))
        const sql = "SELECT g.id,coalesce(g.name,'') name,coalesce(g.name_de,'') name_de,coalesce(g.brand,'') brand," +
            "coalesce(g.brand_relation,'') brand_relation,coalesce(g.barcode,'') barcode,coalesce(g.unit,'g') unit," +
            "coalesce(g.serving_size,0) serving_size,coalesce(g.calories,0) calories,coalesce(g.carbs,0) carbs," +
            "coalesce(g.protein,0) protein,coalesce(g.fat,0) fat,coalesce(g.sugar,0) sugar,coalesce(g.fiber,0) fiber," +
            "coalesce(g.saturated_fat,0) saturated_fat,coalesce(g.salt,0) salt,coalesce(g.moderation_status,'') moderation_status," +
            "coalesce(g.creator,'') creator,coalesce(g.source,'') source,coalesce(g.source_id,'') source_id,0 is_fruit FROM global_foods_fts f " +
            "JOIN global_foods g ON g.id=f.record_id WHERE global_foods_fts MATCH {:match} AND g.moderation_status='approved' " +
            "ORDER BY CASE " +
            "WHEN lower(replace(replace(g.brand,char(39),''),'’',''))=" +
            "lower(replace(replace({:query},char(39),''),'’','')) THEN 0 " +
            "WHEN g.source='manufacturer' AND coalesce(g.brand,'')<>'' AND " +
            "lower(replace(replace({:query},char(39),''),'’','')) LIKE " +
            "lower(replace(replace(g.brand,char(39),''),'’','')) || ' %' THEN 1 " +
            "WHEN lower({:query})='döner' AND g.source='bls' AND lower(g.name_de) LIKE 'döner kebab%' THEN 1 " +
            "WHEN g.source IN ('bls','usda_fdc','health_canada','seed') AND coalesce(g.brand,'')='' " +
            "AND (lower(g.name_de)=lower({:raw}) OR lower(g.name)=lower({:raw})) THEN 1 " +
            "WHEN g.source IN ('bls','usda_fdc','health_canada','seed') AND coalesce(g.brand,'')='' " +
            "AND (lower(g.name_de)=lower({:query}) OR lower(g.name)=lower({:query}) " +
            "OR lower(g.name_de) LIKE lower({:wordPrefix}) OR lower(g.name) LIKE lower({:wordPrefix})) THEN 2 " +
            "WHEN lower(g.name_de)=lower({:query}) OR lower(g.name)=lower({:query}) THEN 3 " +
            "WHEN lower(g.name_de) LIKE lower({:wordPrefix}) OR lower(g.name) LIKE lower({:wordPrefix}) THEN 4 " +
            "WHEN lower(g.name_de) LIKE lower({:prefix}) OR lower(g.name) LIKE lower({:prefix}) THEN 5 " +
            "ELSE 6 END,CASE WHEN g.source='manufacturer' THEN 0 WHEN g.source IN ('bls','usda_fdc','health_canada','seed') THEN 1 ELSE 2 END," +
            "bm25(global_foods_fts),g.off_unique_scans DESC LIMIT 80"
        $app.dao().db().newQuery(sql).bind({ match:
            tokens.map((value) => '"' + value.replace(/"/g, '""') + '"*').join(" AND "),
            query: rankingQuery,
            raw: rankingQuery + " roh",
            wordPrefix: rankingQuery + " %",
            prefix: rankingQuery + "%"
        }).all(rows)
        return c.json(200, { items: rows })
    } catch (error) {
        $app.logger().error("Global food FTS search failed", "error", String(error))
        // A LIKE scan over the full catalogue previously held SQLite for up to
        // several minutes. Fail fast so the client can retry instead.
        throw new ApiError(503, "Global food search is temporarily unavailable.")
    }
}, $apis.requireRecordAuth("users"))
