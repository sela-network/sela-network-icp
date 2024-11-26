import React from 'react';
import { BarChart } from '@mui/x-charts';

import { dataset, series } from '../samples/data';

export default function StackBars() {
  return (
    <BarChart
      dataset={dataset()}
      series={series}
      slotProps={{
        legend: { hidden: true },
      }}
      height={500}
      borderRadius={4}
      leftAxis={null}
      xAxis={[
        {
          scaleType: 'band',
          dataKey: 'date',
          categoryGapRatio: 0.5,
          barGapRatio: 0.5,
        },
      ]}
      sx={{
        '& .MuiChartsAxis-tickLabel tspan': {
          fill: '#fff !important',
          fontSize: '8px',
        },
      }}
    />
  );
}
