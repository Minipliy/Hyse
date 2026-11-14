const text = (value) => String(value || "").trim().replace(/\s+/g, " ")
const number = (value) => {
    const parsed = Number(value || 0)
    return isFinite(parsed) && parsed >= 0 ? parsed : 0
}
const snapshot = (value) => value && typeof value === "object" ? value : {}
const units = ["g", "ml", "oz", "fl oz"]
const unit = (value) => units.includes(String(value || "")) ? String(value) : "g"

const key = (value) => {
    const ingredients = Array.isArray(value.ingredients) ? value.ingredients : []
    const parts = ingredients.map((ingredient) => {
        const food = ingredient && typeof ingredient.food === "object" ? ingredient.food : {}
        return [text(food.name).toLocaleLowerCase("en-US"), unit(ingredient.unit), Math.round(number(ingredient.grams) * 1000) / 1000].join(":")
    }).sort()
    return [text(value.name).toLocaleLowerCase("en-US"), parts.join("|"), Math.round(number(value.servings) * 1000) / 1000].join("|")
}

const nutrients = (value) => {
    const result = { calories: 0, carbs: 0, protein: 0, fat: 0, sugar: 0, fiber: 0, saturated_fat: 0, salt: 0 }
    const mappings = { calories: "kcalPer100g", carbs: "carbsPer100g", protein: "proteinPer100g", fat: "fatPer100g", sugar: "sugarPer100g", fiber: "fiberPer100g", saturated_fat: "saturatedFatPer100g", salt: "saltPer100g" }
    const ingredients = Array.isArray(value.ingredients) ? value.ingredients : []
    for (const ingredient of ingredients) {
        const food = ingredient && typeof ingredient.food === "object" ? ingredient.food : {}
        const factor = number(ingredient.grams) / 100
        for (const name in mappings) result[name] += number(food[mappings[name]]) * factor
    }
    return result
}

module.exports = { text, number, snapshot, unit, key, nutrients }
