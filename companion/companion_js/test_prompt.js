// Test script for verifying system prompt behavior and conditional question_type.
const path = require("path");
const fs = require("fs");
const dotenv = require("dotenv");

// Load .env
const envCandidates = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, ".env")
];
for (const cand of envCandidates) {
  if (fs.existsSync(cand)) {
    dotenv.config({ path: cand });
    break;
  }
}

const { runOpenAIFlow } = require("./companion-agent-services");

async function runTests() {
  const testCases = [
    {
      name: "Dish Advice Comparison (Should have question_type)",
      prompt: "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。"
    },
    {
      name: "Meal Record (Should NOT have question_type)",
      prompt: "我今天中午吃了一碗牛肉拉麵"
    },
    {
      name: "General Chat (Should NOT have question_type)",
      prompt: "今天天氣真好，陪我聊聊！"
    },
    {
      name: "Medical Out-of-Scope (Should NOT have question_type)",
      prompt: "這個降血糖藥我應該怎麼服用？請幫我診斷。"
    },
    {
      name: "Dish Translation 1 - Milk Tea and Beef Burger (Should translate dishes)",
      prompt: "我今天喝了波霸鮮奶茶搭配起司瀑布超厚牛肉堡"
    },
    {
      name: "Dish Translation 2 - Fancy Teas (Should translate and compare dishes)",
      prompt: "我想喝翡翠厚乳跟水玉冷露，哪一個糖分低？"
    }
  ];

  console.log("Starting LLM Prompt & Schema verification...\n");

  for (const tc of testCases) {
    console.log(`[Test Case] ${tc.name}`);
    console.log(`Input: "${tc.prompt}"`);
    try {
      const result = await runOpenAIFlow(tc.prompt);
      console.log("Result Screening:", JSON.stringify(result.screening, null, 2));
      console.log("Result Emotion:", JSON.stringify(result.emotion, null, 2));
      console.log("-------------------------------------------\n");
    } catch (err) {
      console.error("Test Case Failed with error:", err.message);
      console.log("-------------------------------------------\n");
    }
  }
}

runTests();
