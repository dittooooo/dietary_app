const {
  generateCompanionReply: runLLMReply
} = require("./companion-llm");

function displayDietGoal(value) {
  const normalized = String(value || "").trim();
  const upper = normalized.toUpperCase();
  if (["LOSE_WEIGHT", "LOSE_FAT"].includes(upper)) return "減脂";
  if (upper === "GAIN_MUSCLE") return "增肌";
  if (upper === "MAINTAIN") return "養生";
  return normalized;
}

function displayHealthCondition(value) {
  const normalized = String(value || "").trim();
  const labels = {
    GERD: "胃食道逆流",
    HYPERTENSION: "高血壓",
    HYPERLIPIDEMIA: "高血脂",
    DIABETES: "糖尿病",
    CARDIOVASCULAR: "心血管疾病",
    KIDNEY_DISEASE: "慢性腎臟病",
    METABOLIC_SYNDROME: "代謝症候群",
    GOUT: "痛風",
    HYPERURICEMIA: "高尿酸血症",
    NONE: "無疾病"
  };
  return labels[normalized.toUpperCase()] || normalized;
}

/**
 * 產生陪伴精靈的最終回覆
 * 整合意圖、情緒以及飲食助理的回應，透過 LLM 生成溫馨、同理心且在地化的回覆。
 * @param {Object} params - 參數物件，包含篩選結果、情緒分析、飲食助理回應、原始問題與歷史紀錄等
 * @returns {Promise<string>} 最終要呈現給使用者的對話文字
 */
async function getCompanionReply({
  screening,
  emotion,
  dietaryAgentResponse,
  userPrompt,
  dietaryAgentError,
  userProfileContext,
  tempStory = []
}) {
  const localizedProfileContext = userProfileContext
    ? {
        ...userProfileContext,
        dietGoal: displayDietGoal(userProfileContext.dietGoal),
        healthConditions: Array.isArray(userProfileContext.healthConditions)
          ? userProfileContext.healthConditions.map(displayHealthCondition).filter(Boolean)
          : []
      }
    : null;

  // 飲食紀錄意圖處理 (分流 B 極速卡片數據與成功對話組裝，由前端實作延遲渲染)
  if (screening?.intent_category === "meal_record") {
    if (Array.isArray(screening.meal_items) && screening.meal_items.length > 0) {
      return dietaryAgentResponse
        ? `已成功幫你將飲食存入紀錄庫囉！`
        : `我先整理好飲食紀錄草稿了，請確認內容後再儲存喔！`;
    } else {
      return `收到你想記錄飲食，但似乎沒有聽到具體的餐點名稱。你可以再跟我說一次你吃了什麼喔！`;
    }
  }

  // 飲食紀錄查詢意圖處理 (分流 D 極速日期卡片對話組裝)
  if (screening?.intent_category === "meal_query") {
    if (screening.query_date) {
      const dateParts = screening.query_date.split("-");
      const formattedDateStr = dateParts.length === 3
        ? `${parseInt(dateParts[1], 10)}/${parseInt(dateParts[2], 10)}`
        : screening.query_date;
      return `幫你找到 ${formattedDateStr} 號的飲食紀錄囉！請在下方卡片確認當天記錄的內容吧！`;
    } else {
      return `收到你想查詢歷史飲食紀錄，但似乎沒有聽到具體的日期。你可以再跟我說一次你想看哪一天的紀錄喔！（例如：「我 6/19 吃了什麼」）`;
    }
  }

  // 進入 Stage 3 LLM 生成對話回覆 (100% 集中注入 Persona 靈魂，動態應答各種情境與異常)
  let finalReply = "";
  try {
    finalReply = await runLLMReply({
      userPrompt,
      screening,
      emotion,
      dietaryAgentResponse,
      dietaryAgentError,
      userProfileContext: localizedProfileContext,
      tempStory
    });
  } catch (error) {
    // 當 LLM 回覆生成崩潰或連線失敗時 (OpenAI API 保底)
    console.error("Failed to generate companion response with LLM:", error.message);
    finalReply = "AI 功能目前發生異常，請稍後再試。";
  }

  return finalReply;
}

// 匯出外部服務層的核心函數
module.exports = {
  getCompanionReply
};
