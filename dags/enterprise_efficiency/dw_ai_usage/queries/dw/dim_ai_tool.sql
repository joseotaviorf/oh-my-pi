SELECT
    t.sk_ai_tool,
    t.tool,
    t.tool_name
FROM (
    VALUES
        (1, 'claude', 'Claude'),
        (2, 'cursor', 'Cursor'),
        (3, 'gemini', 'Gemini')
) AS t(sk_ai_tool, tool, tool_name)
