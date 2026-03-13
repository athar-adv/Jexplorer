import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  //Svg: React.ComponentType<React.ComponentProps<'svg'>>;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Quality of Life',
    //Svg: require('@site/static/img/noob.jpg').default,
    description: (
      <>
        Jexplorer was designed with quality of life in mind, with many QOL tools such as built-in reclass,
        GitHub pull/push, duplicate increments name if it has a numeric suffix,
        ancestors are sticky stacked to the top edge of the viewport, etc.
      </>
    ),
  },
  {
    title: 'Customizable',
    //Svg: require('@site/static/img/editorwidgets.png').default,
    description: (
      <>
        Jexplorer is highly extendable and customizable, with many editor widgets openable via the top-left
        options menu (with 3 dots) allowing you to change a part you don&apos;t like, ontop of being open source.
      </>
    ),
  },
  {
    title: 'Performant & Professional',
    //Svg: require('@site/static/img/verscontrol.png').default,
    description: (
      <>
        Jexplorer was designed from the ground up to be performant &amp; efficient, with it
        having a much better ambient &amp; active performance than Roblox&apos;s default Explorer.
        The UI is sleek and user-friendly, making for a nice experience.
      </>
    ),
  },
];

function Feature({title, /*Svg,*/ description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
