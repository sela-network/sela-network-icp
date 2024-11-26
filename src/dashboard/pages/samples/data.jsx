import Color from '../../style/Color';

const dataset = () => {
  let data = [];

  for (let i = 1; i <= 31; i++) {
    const number1 = Math.floor(Math.random() * (200 - 150 + 1)) + 150;
    const number2 = Math.floor(Math.random() * (200 - 150 + 1)) + 150;
    const number3 = Math.floor(Math.random() * (200 - 150 + 1)) + 150;
    data.push({
      date: `${i}-11`,
      node: number1,
      referral: number2,
      bonus: number3,
    });
  }

  return data;
};

const series = [
  {
    dataKey: 'bonus',
    label: 'Bonus',
    stack: 'points',
    color: Color.darkOrange,
  },
  {
    dataKey: 'referral',
    label: 'Referral',
    stack: 'points',
    color: Color.orange,
  },
  {
    dataKey: 'node',
    label: 'Node',
    stack: 'points',
    color: Color.yellow,
  },
];

export { dataset, series };
