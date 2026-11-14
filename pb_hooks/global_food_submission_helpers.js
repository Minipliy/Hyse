const text = (value) => String(value || "").trim().replace(/\s+/g, " ")

const barcode = (value) => {
    const raw = text(value)
    if (!raw) return ""
    if (!/^[0-9\s.\-–—]+$/.test(raw)) throw new BadRequestError("Barcode contains invalid characters.")
    const digits = raw.replace(/[^0-9]/g, "")
    if ([8, 12, 13, 14].indexOf(digits.length) < 0) throw new BadRequestError("Unsupported barcode length.")
    let sum = 0
    for (let i = digits.length - 2, offset = 0; i >= 0; i--, offset++) sum += Number(digits[i]) * (offset % 2 === 0 ? 3 : 1)
    if ((10 - sum % 10) % 10 !== Number(digits[digits.length - 1])) throw new BadRequestError("Invalid barcode check digit.")
    return digits
}

const number = (value) => {
    const parsed = Number(value || 0)
    if (!isFinite(parsed) || parsed < 0) throw new BadRequestError("Nutrition values must be non-negative numbers.")
    return Math.round(parsed * 10000) / 10000
}

const snapshotFields = ["name", "brand", "barcode", "unit", "serving_size", "calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt", "is_fruit"]
const foodUnits = ["g", "ml", "oz", "fl oz"]
const foodUnit = (value) => foodUnits.includes(String(value || "")) ? String(value) : "g"

const key = (record) => {
    const nutrients = ["calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt"].map((name) => number(record.get(name)))
    return [text(record.get("name")).toLocaleLowerCase("en-US"), text(record.get("brand")).toLocaleLowerCase("en-US"), foodUnit(record.get("unit")), number(record.get("serving_size"))].concat(nutrients).join("|")
}

const fillSubmission = (submission, data) => {
    const name = text(data.name)
    if (!name) throw new BadRequestError("A food name is required.")
    submission.set("name", name)
    submission.set("brand", text(data.brand))
    submission.set("barcode", barcode(data.barcode))
    submission.set("unit", foodUnit(data.unit))
    for (const name of ["serving_size", "calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt"]) submission.set(name, number(data[name]))
    submission.set("is_fruit", !!data.is_fruit)
    submission.set("reviewed_by", "")
    submission.set("reviewed_at", "")
    submission.set("rejection_reason", "")
}

const normalizedBrandName = (value) => text(value).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("en-US").replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ")

// Resolve both modern relation IDs and plain brand names from older/offline
// clients. A newly encountered brand is immediately part of the global brand
// catalogue; food publication therefore never leaves a private brand behind.
const resolveGlobalBrand = (dao, requestedID, requestedName, creatorID) => {
    const name = text(requestedName).slice(0, 160)
    let brand = null
    let needsSave = false
    const brandID = text(requestedID)
    if (brandID) {
        try { brand = dao.findRecordById("global_brands", brandID) } catch (_) {}
    }
    const normalized = normalizedBrandName(name)
    if (!brand && normalized) {
        try { brand = dao.findFirstRecordByFilter("global_brands", "normalized_name = {:name}", { name: normalized }) } catch (_) {}
    }
    if (brand && String(brand.get("status")) === "merged") {
        const targetID = String(brand.get("merged_into") || "")
        brand = targetID ? dao.findRecordById("global_brands", targetID) : null
    }
    if (!brand && normalized) {
        brand = new Record(dao.findCollectionByNameOrId("global_brands"))
        brand.set("name", name)
        brand.set("normalized_name", normalized)
        brand.set("slug", normalized.replace(/\s+/g, "-"))
        brand.set("aliases", [])
        brand.set("created_by", creatorID)
        needsSave = true
    }
    if (!brand) return null
    if (String(brand.get("status")) !== "approved") {
        brand.set("status", "approved")
        brand.set("reviewed_by", creatorID)
        brand.set("reviewed_at", new Date().toISOString())
        needsSave = true
    }
    if (needsSave) dao.saveRecord(brand)
    return brand
}

module.exports = { text, barcode, number, snapshotFields, foodUnit, key, fillSubmission, resolveGlobalBrand }
