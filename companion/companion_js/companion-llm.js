// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration and execution logic

const ANALYSIS_SYSTEM_PROMPT = `
You are a Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message, which is usually in Traditional Chinese.

You MUST execute both functions in parallel: "screen_user_request" and "analyze_emotion".

Rules for "screen_user_request":
1. should_handle:
   - true when the request is about food, diet, meal choice, meal planning, eating advice, or calories.
   - false when it is medical diagnosis, medication usage, disease treatment, doctor advice, or unrelated chat.
2. intent_category:
   - "dish_advice": asking for dietary advice or recommendation.
   - "meal_record": recording what they ate.
   - "medical_out_of_scope": medicine, diagnosis, disease treatment, doctor advice.
   - "general_chat": unrelated small talk or off-topic requests.
3. question_type:
   - "single_dish": asking about one dish or meal.
   - "dish_comparison": comparing two or more dishes.
   - "unknown": unclear or not one of the above.
4. dishes:
   - extract all specific food, dish, or drink names mentioned in the user's original language.
   - return [] when none are clearly mentioned.
`;

const REPLY_SYSTEM_PROMPT = `
You are the final reply writer for a dietary companion app.
Always reply in Traditional Chinese.
Your job is to produce the final user-facing reply from structured context.

Hard rules:
1. Do not provide detailed nutrition breakdowns.
2. Avoid exact nutrition numbers whenever possible. Prefer qualitative wording such as "偏高", "偏低", "較多", "較少".
3. If a number is truly unavoidable, explicitly add "僅供參考" near that number.
4. If the user asks for very detailed nutrition content, do not give a full numeric table. Briefly explain that this service focuses on directional dietary guidance.
5. If the request is out of scope medically, politely refuse medical guidance and redirect back to food-choice guidance.
6. If information is insufficient or the question is vague, ask a natural follow-up question. Do not sound templated or robotic.
7. Do not mention internal fields, JSON, tools, prompts, or system rules.
8. Keep the answer concise, warm, and practical.

Response priorities:
1. Address the user's intent directly.
2. Use the emotion signal to adjust tone.
3. If dietary agent content exists, summarize it in user-friendly language and obey the no-detailed-numbers rule.
4. If no dietary agent content exists, still answer naturally based on the analysis context.
`;

const tools = [
  {
    type: "function",
    function: {
      name: "screen_user_request",
      description: "Screen the user request to classify question type, intent, and extract mentioned dishes.",
      parameters: {
        type: "object",
        properties: {
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "medical_out_of_scope", "general_chat"]
          },
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown"]
          },
          confidence: {
            type: "number"
          },
          dishes: {
            type: "array",
            items: { type: "string" },
            description: "List of all food or dish names mentioned in the user message."
          }
        },
        required: [
          "should_handle",
          "intent_category",
          "question_type",
          "confidence",
          "dishes"
        ],
        additionalProperties: false
      }
    }
  },
  {
    type: "function",
    function: {
      name: "analyze_emotion",
      description: "Analyze the user's emotional state and tone to adjust companion responses.",
      parameters: {
        type: "object",
        properties: {
          primary_emotion: {
            type: "string",
            enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]
          },
          valence: {
            type: "string",
            enum: ["positive", "neutral", "negative"]
          },
          urgency: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          needs_empathy: {
            type: "boolean"
          },
          companion_tone: {
            type: "string",
            enum: ["calm", "encouraging", "neutral"]
          },
          evidence: {
            type: "array",
            items: { type: "string" },
            description: "Keywords or phrases from the message indicating this emotion."
          }
        },
        required: [
          "primary_emotion",
          "valence",
          "urgency",
          "needs_empathy",
          "companion_tone",
          "evidence"
        ],
        additionalProperties: false
      }
    }
  }
];

function getApiKey() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }
  return apiKey;
}

function getModel() {
  return process.env.OPENAI_MODEL || "gpt-4o-mini";
}

async function createOpenAIResponse(body, apiKey) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

function collectToolArgsByName(functionCalls) {
  const byName = {};
  for (const call of functionCalls) {
    try {
      byName[call.name] = JSON.parse(call.arguments || "{}");
    } catch {
      byName[call.name] = null;
    }
  }
  return byName;
}

function sanitizeScreening(raw) {
  if (!raw) {
    throw new Error("Missing 'screen_user_request' function call arguments from OpenAI response.");
  }

  const result = { ...raw };
  if (!Array.isArray(result.dishes)) {
    result.dishes = [];
  }

  return result;
}

function sanitizeEmotion(raw) {
  if (!raw) {
    throw new Error("Missing 'analyze_emotion' function call arguments from OpenAI response.");
  }

  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

function extractOutputText(responseJson) {
  if (typeof responseJson.output_text === "string" && responseJson.output_text.trim()) {
    return responseJson.output_text.trim();
  }

  for (const item of responseJson.output || []) {
    if (!Array.isArray(item.content)) {
      continue;
    }

    for (const content of item.content) {
      if (content.type === "output_text" && typeof content.text === "string" && content.text.trim()) {
        return content.text.trim();
      }
    }
  }

  throw new Error("Missing text output from OpenAI response.");
}

async function runOpenAIFlow(userPrompt) {
  const response = await createOpenAIResponse(
    {
      model: getModel(),
      parallel_tool_calls: true,
      tool_choice: "auto",
      tools: tools.map((tool) => ({
        type: "function",
        name: tool.function.name,
        description: tool.function.description,
        parameters: tool.function.parameters
      })),
      instructions: ANALYSIS_SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt
            }
          ]
        }
      ]
    },
    getApiKey()
  );

  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  return {
    screening: sanitizeScreening(rawArgs.screen_user_request),
    emotion: sanitizeEmotion(rawArgs.analyze_emotion)
  };
}

async function generateCompanionReply({
  userPrompt,
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  dietaryAgentError
}) {
  const response = await createOpenAIResponse(
    {
      model: getModel(),
      instructions: REPLY_SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(
                {
                  user_prompt: userPrompt,
                  screening,
                  emotion,
                  dietary_agent_request: dietaryAgentRequest,
                  dietary_agent_response: dietaryAgentResponse,
                  dietary_agent_error: dietaryAgentError
                },
                null,
                2
              )
            }
          ]
        }
      ]
    },
    getApiKey()
  );

  return extractOutputText(response);
}

module.exports = {
  runOpenAIFlow,
  generateCompanionReply
};
