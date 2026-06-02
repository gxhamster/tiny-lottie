import { DotLottie } from '@dotlottie/dotlottie-js';
import fs from 'fs';
import path from 'path';

function LoadJsonDataset(dir_path) {
  const files = fs.readdirSync(dir_path);
  const json_files = files.filter(file => !file.startsWith('.') && file.endsWith('.json'));
  const collection = []
  json_files.forEach(file => {
    try {
      const start_time = performance.now()
      const data = fs.readFileSync(path.resolve(dir_path, file), 'utf8');
      const json_data = JSON.parse(data)
      const end_time = performance.now()
      const pair = {
        name: file,
        data: json_data,
        time: end_time - start_time
      }
      collection.push(pair);
      //collection.push(data)
    } catch (err) {
      console.error(`Error reading ${file}:`, err);
    }
  });

  return collection
}

const collection = LoadJsonDataset('./dataset')

async function createDotLottie(name, json_data, json_time){
  const start_time = performance.now()
  const dotLottie = new DotLottie();
  await dotLottie 
        .addAnimation({
          id: name,
          data: json_data,
          loop: true,
          autoplay: true
        })
        .build()
  
  const buffer = await dotLottie.toArrayBuffer();
  const end_time = performance.now()
  const elapsed = end_time - start_time
  console.log("Name =", name, "Length =", buffer.byteLength, "Time=", elapsed + json_time, "ms") 
}

collection.map(({name, data, time}) => {
  createDotLottie(name, data, time)
})

