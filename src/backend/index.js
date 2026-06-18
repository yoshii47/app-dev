// .envを読む方法の手段
require('dotenv').config();
const { getAllProfiles } = require('./src/repositories/profileRepository');

const express = require('express');
const app = express();
const port = 3000;

// JSONデータを扱うためのミドルウェア
app.use(express.json());

app.get('/profiles', async (req, res) => {
  const profiles = await getAllProfiles();
  res.json(profiles);
});


app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});

