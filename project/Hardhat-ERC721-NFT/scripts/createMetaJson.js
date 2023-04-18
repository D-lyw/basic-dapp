const fs = require('fs')

const allMeta = fs.readFileSync('../data/allNFTMeta.json')

// template NFT meta json
const template = {
  name: 'Axe Game',
  description:
    'A fun and profitable blockchain game，you can rent it in the Rentero market',
  external_link: 'https://rentero.io',
  attributes: [],
  image: '',
}

const list = JSON.parse(allMeta)

// 生成 90 个 NFT metadata json 数据
const totalList = [...list, ...list, ...list]

const BASE_IPFS = `https://gateway.pinata.cloud/ipfs/Qmch5cWePWcGUxBG21suaA5XdVHFGDuPbk9do9CJVvKNFr/`

totalList.map((item, index) => {
  const { magic, quality, physical, crit, attack, defense, level } = item
  const attributes = [
    {
      trait_type: 'Magic Type',
      value: magic,
    },
    {
      trait_type: 'Quality',
      value: quality,
    },
    {
      trait_type: 'Physical Damage',
      value: parseInt(physical),
    },
    {
      trait_type: 'Crit Chance',
      value: parseInt(crit),
    },
    {
      trait_type: 'Attack Speed',
      value: parseInt(attack),
    },
    {
      trait_type: 'Defense',
      value: parseInt(defense),
    },
    {
      trait_type: 'Level',
      value: parseInt(level),
    },
  ]

  const imageIndex = (index % 30) + 1
  const image = `${BASE_IPFS}${imageIndex}.png`

  const NFTJson = {
    ...template,
    attributes,
    image,
  }

  fs.writeFileSync(
    `../data/meta-json/${index + 1}.json`,
    JSON.stringify(NFTJson)
  )
})
