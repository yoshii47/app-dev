// .envを読む方法の手段
require('dotenv').config();
const { getAllProfiles } = require('./src/repositories/profileRepository');

const express = require('express');
const app = express();
const port = 3000;

app.get('/users', (req, res) => {
  res.json(users);
});

// JSONデータを扱うためのミドルウェア
app.use(express.json());



app.get('/users/:id', (req, res) => {
  const id = Number(req.params.id);
  const user = users.find(u => u.id === id);
  if (user) {
    res.json(user);
  } else {
    res.status(404).send('ユーザーが見つかりません');
  }
});


app.get('/profiles', async (req, res) => {
  const profiles = await getAllProfiles();
  res.json(profiles);
});


app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});

