# xforce_AI Nushell configuration

def show-models [] {
  let candidates = [
    "/workspace/models"
    "/workspace/.cache/huggingface"
    "/home/user/.cache/huggingface"
  ]

  let found = ($candidates | where {|path| $path | path exists })

  if ($found | is-empty) {
    print "No local model directories found. Try /workspace/models or Hugging Face caches under /workspace/.cache/huggingface."
    return
  }

  $found | each {|path|
    let entries = (try { ls $path | select name type size modified } catch { [] })
    {
      path: $path,
      entries: $entries
    }
  }
}

def call-llm [prompt?: string] {
  let piped = (try { $in } catch { null })
  let request = if ($prompt != null) { $prompt } else if ($piped != null) { $piped | into string } else { "" }

  if (which xforce-call-llm | is-not-empty) {
    if ($request | is-empty) {
      xforce-call-llm
    } else {
      $request | xforce-call-llm
    }
    return
  }

  if ($request | is-empty) {
    print "call-llm is ready, but no local LLM backend is installed yet. Usage: call-llm 'hello' or 'hello' | call-llm"
  } else {
    print $"call-llm placeholder: no local LLM backend is installed yet. Received prompt: ($request)"
  }
}
