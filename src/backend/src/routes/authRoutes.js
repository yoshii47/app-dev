const express = require('express')
const router = express.Router();
const bcrypt = require('bcrypt');
const {findUserByEmail , createUser} = require('./../repositories/userRepository');
const {createProfile} = require('./../repositories/profileRepository');

router.post('/register',async (req , res) => {
    const {email ,password} = req.body;

    const existingUser = await findUserByEmail(email);
    if (existingUser){
        return res.status(409).json({error:'このメールアドレスはすでに登録されています'});
    }

    const hash = await bcrypt.hash(password , 10);

    const createU = await createUser(email,hash);

    const createP = await createProfile(id);

    res.status(201).json({massage:'登録が完了しました'});
})

module.exports = router;