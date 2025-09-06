// Firebase Functions (Node.js, v1 API) — lint-friendly
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// HTTP: GET https://<region>-<project>.cloudfunctions.net/helloWorld
exports.helloWorld = functions.https.onRequest((req, res) => {
  res.json({message:"Hello from Firebase Functions!"});
});

// Callable: call from Flutter/JS with an optional name
exports.helloCallable = functions.https.onCall((data, context) => {
  const nameRaw = data && typeof data.name === 'string' ? data.name : undefined;
  const name = nameRaw || 'World';
  return {message:`Hello, ${name}!`};
});

// Helper: extract a summary string from Exa response
function pickSummary(obj){
  try{
    if(!obj || typeof obj!=='object') return '';
    if(typeof obj.summary==='string') return obj.summary;
    if(Array.isArray(obj.results)){
      for(const it of obj.results){
        if(it && typeof it.summary==='string') return it.summary;
        if(it && it.content && typeof it.content.summary==='string') return it.content.summary;
      }
    }
    if(Array.isArray(obj.documents)){
      for(const d of obj.documents){
        if(d && typeof d.summary==='string') return d.summary;
      }
    }
    return '';
  }catch(_){ return ''; }
}

// HTTP: GET/POST https://<region>-<project>.cloudfunctions.net/exaSummary
// Calls Exa API and returns only the summary text.
exports.exaSummary = functions.https.onRequest(async (req, res) => {
  try {
    const apiKey = process.env.EXA_API_KEY;
    if(!apiKey){
      res.status(500).json({error:"Missing EXA_API_KEY environment variable"});
      return;
    }

    const urls = [
      "https://www.google.com/maps/contrib/115444186411517945794/reviews/@41.4688643,-81.1138728,7z/data=!3m1!4b1!4m3!8m2!3m1!1e1?authuser=4&entry=ttu&g_ep=EgoyMDI1MDkwMy4wIKXMDSoASAFQAw%3D%3D"
    ];
    const summaryQuery = "what food and places does he like? describe both food preferences and travel/place preferences";

    const response = await fetch("https://api.exa.ai/contents",{
      method:"POST",
      headers:{"content-type":"application/json","x-api-key":apiKey},
      body:JSON.stringify({urls:urls,summary:{query:summaryQuery},livecrawl_timeout:10000,text:true})
    });

    if(!response.ok){
      const text = await response.text();
      res.status(500).json({error:`Exa API error ${response.status}`,details:text});
      return;
    }

    const result = await response.json();
    const summary = pickSummary(result) || "No summary available.";
    res.json({summary:summary});
  } catch (err) {
    res.status(500).json({error:String((err&&err.message)||err)});
  }
});

// Callable: Returns only the Exa AI summary for a hard-coded query and URL
exports.exaSummaryCallable = functions.https.onCall(async (data, context) => {
  try{
    const apiKey = process.env.EXA_API_KEY;
    if(!apiKey){
      throw new functions.https.HttpsError('failed-precondition','Missing EXA_API_KEY environment variable');
    }

    const urls = [
      "https://www.google.com/maps/contrib/115444186411517945794/reviews/@41.4688643,-81.1138728,7z/data=!3m1!4b1!4m3!8m2!3m1!1e1?authuser=4&entry=ttu&g_ep=EgoyMDI1MDkwMy4wIKXMDSoASAFQAw%3D%3D"
    ];
    const summaryQuery = "what food and places does he like? describe both food preferences and travel/place preferences";

    const response = await fetch("https://api.exa.ai/contents",{
      method:"POST",
      headers:{"content-type":"application/json","x-api-key":apiKey},
      body:JSON.stringify({urls:urls,summary:{query:summaryQuery},livecrawl_timeout:10000,text:true})
    });

    if(!response.ok){
      const text = await response.text();
      throw new functions.https.HttpsError('internal',`Exa API error ${response.status}`,text);
    }

    const result = await response.json();
    const summary = pickSummary(result) || "No summary available.";
    return {summary:summary};
  }catch(err){
    if(err && err.code && err.code.startsWith && err.code.startsWith('functions/')){throw err;}
    throw new functions.https.HttpsError('internal',String((err&&err.message)||err));
  }
});


